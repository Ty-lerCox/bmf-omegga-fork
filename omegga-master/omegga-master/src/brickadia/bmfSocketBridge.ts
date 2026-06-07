import { randomBytes, randomInt } from 'node:crypto';
import EventEmitter from 'node:events';
import { createServer, Server, Socket } from 'node:net';

type ClientRole = 'bmf-native' | 'plugin' | 'unknown';

type ClientState = {
  authenticated: boolean;
  role: ClientRole;
  buffer: string;
};

type BridgeMessage = {
  type?: string;
  id?: string;
  token?: string;
  role?: string;
};

const DEFAULT_HOST = '127.0.0.1';
const DEFAULT_PORT_MIN = 26000;
const DEFAULT_PORT_MAX = 61000;

export default class BmfSocketBridgeHost extends EventEmitter {
  readonly token = randomBytes(16).toString('hex');
  readonly host: string;
  readonly port: number;

  #server: Server = null;
  #clients = new Map<Socket, ClientState>();
  #bmfClients = new Set<Socket>();
  #stopped = true;

  constructor(options: { host?: string; port?: number } = {}) {
    super();
    this.host = options.host || process.env.OMEGGA_BMF_SOCKET_HOST || DEFAULT_HOST;
    this.port =
      options.port ||
      Number(process.env.OMEGGA_BMF_SOCKET_PORT || 0) ||
      randomInt(DEFAULT_PORT_MIN, DEFAULT_PORT_MAX);
  }

  start() {
    this.stop();
    this.#stopped = false;
    this.#server = createServer(socket => this.handleConnection(socket));
    this.#server.on('error', error => {
      this.emit('log', {
        level: 'error',
        message: `BMF socket bridge failed: ${
          error instanceof Error ? error.message : String(error)
        }`,
      });
    });
    this.#server.listen(this.port, this.host, () => {
      this.emit('ready', {
        host: this.host,
        port: this.port,
        transport: 'socket',
      });
    });

    return {
      OMEGGA_BMF_SOCKET_ENABLED: '1',
      OMEGGA_BMF_SOCKET_HOST: this.host,
      OMEGGA_BMF_SOCKET_PORT: String(this.port),
      OMEGGA_BMF_SOCKET_TOKEN: this.token,
      OMEGGA_BMF_SOCKET_POLL_MS: process.env.OMEGGA_BMF_SOCKET_POLL_MS || '25',
    };
  }

  stop() {
    for (const socket of this.#clients.keys()) {
      socket.removeAllListeners();
      socket.destroy();
    }
    this.#clients.clear();
    this.#bmfClients.clear();

    if (this.#server) {
      this.#server.removeAllListeners();
      this.#server.close();
      this.#server = null;
    }
    this.#stopped = true;
    this.emit('stopped');
  }

  private handleConnection(socket: Socket) {
    socket.setNoDelay(true);
    this.#clients.set(socket, {
      authenticated: false,
      role: 'unknown',
      buffer: '',
    });

    socket.on('data', chunk => this.handleData(socket, chunk));
    socket.on('close', () => this.removeClient(socket));
    socket.on('error', error => {
      this.emit('log', {
        level: 'warn',
        message: `BMF socket client error: ${
          error instanceof Error ? error.message : String(error)
        }`,
      });
      this.removeClient(socket);
    });
  }

  private handleData(socket: Socket, chunk: Buffer) {
    const client = this.#clients.get(socket);
    if (!client) return;

    client.buffer += chunk.toString('utf8');
    if (client.buffer.length > 1024 * 1024) {
      socket.destroy(new Error('BMF socket client exceeded input buffer limit.'));
      return;
    }

    const lines = client.buffer.split(/\r?\n/);
    client.buffer = lines.pop() ?? '';
    for (const line of lines) {
      this.handleLine(socket, client, line);
    }
  }

  private handleLine(socket: Socket, client: ClientState, line: string) {
    const trimmed = line.trim();
    if (!trimmed) return;

    let message: BridgeMessage;
    try {
      message = JSON.parse(trimmed) as BridgeMessage;
    } catch {
      this.emit('log', { level: 'warn', message: 'BMF socket ignored invalid JSON.' });
      return;
    }

    if (!client.authenticated) {
      if (message.type !== 'hello' || message.token !== this.token) {
        socket.destroy(new Error('BMF socket authentication failed.'));
        return;
      }
      client.authenticated = true;
      client.role = this.normalizeRole(message.role);
      if (client.role === 'bmf-native') {
        this.#bmfClients.add(socket);
      }
      this.emit('client', {
        role: client.role,
        bmfClients: this.#bmfClients.size,
        clients: this.#clients.size,
      });
      return;
    }

    if (client.role === 'bmf-native') {
      this.broadcast(trimmed, socket, socket => this.#clients.get(socket)?.role !== 'bmf-native');
      return;
    }

    if (message.type === 'command' || message.type === 'ping') {
      if (this.#bmfClients.size === 0) {
        socket.write(
          `${JSON.stringify({
            type: 'response',
            id: message.type === 'command' ? message.id : undefined,
            ok: false,
            detail: 'no bmf-native clients connected',
          })}\n`,
        );
        return;
      }
      this.broadcast(trimmed, socket, socket => this.#bmfClients.has(socket));
    }
  }

  private normalizeRole(value: string | undefined): ClientRole {
    const role = String(value || '').trim().toLowerCase();
    if (role === 'bmf-native') return 'bmf-native';
    if (role === 'cityrpg' || role === 'plugin') return 'plugin';
    return 'unknown';
  }

  private broadcast(
    line: string,
    sender: Socket,
    predicate: (socket: Socket) => boolean,
  ) {
    const payload = `${line}\n`;
    for (const socket of this.#clients.keys()) {
      if (socket === sender) continue;
      if (!predicate(socket)) continue;
      if (socket.destroyed || !socket.writable) continue;
      socket.write(payload);
    }
  }

  private removeClient(socket: Socket) {
    if (!this.#clients.has(socket)) return;
    this.#clients.delete(socket);
    this.#bmfClients.delete(socket);
    socket.removeAllListeners();
    if (!this.#stopped) {
      this.emit('client', {
        bmfClients: this.#bmfClients.size,
        clients: this.#clients.size,
      });
    }
  }
}
