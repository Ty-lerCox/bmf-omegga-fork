#!/usr/bin/env node

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const assert = require("node:assert/strict");
const zlib = require("node:zlib");
const Database = require("C:/Users/tycox/OneDrive/Documents/GitHub/Brickadia/omegga-master/omegga-master/node_modules/better-sqlite3");
const { parseBrz, decompressChunk } = require("./inspect-brz");
const { convertBrzToBrdb } = require("./convert-brz-to-brdb");

function usage() {
  console.error(
    "Usage: node test-brz-bridge.js <sample.brz>"
  );
}

function reconstructBrdbPaths(db) {
  const rows = db.prepare(`
    WITH RECURSIVE folder_paths(folder_id, path) AS (
      SELECT folder_id, name
      FROM folders
      WHERE parent_id IS NULL
      UNION ALL
      SELECT f.folder_id, folder_paths.path || '/' || f.name
      FROM folders f
      JOIN folder_paths ON f.parent_id = folder_paths.folder_id
    )
    SELECT files.file_id,
           CASE
             WHEN folder_paths.path IS NULL THEN files.name
             ELSE folder_paths.path || '/' || files.name
           END AS path,
           blobs.compression,
           blobs.size_uncompressed,
           blobs.size_compressed,
           blobs.hash,
           blobs.content
    FROM files
    LEFT JOIN folder_paths ON files.parent_id = folder_paths.folder_id
    LEFT JOIN blobs ON files.content_id = blobs.blob_id
    WHERE files.deleted_at IS NULL
    ORDER BY path
  `).all();
  return rows;
}

function readBrdbFileContent(row) {
  if (row.content == null) {
    return null;
  }
  if (!row.compression || row.size_compressed >= row.size_uncompressed) {
    return row.content;
  }
  return zlib.zstdDecompressSync(row.content, {
    maxOutputLength: row.size_uncompressed,
    params: {},
  });
}

function main(argv) {
  if (argv.length < 1) {
    usage();
    process.exitCode = 1;
    return;
  }

  const inputPath = argv[0];
  const parsed = parseBrz(inputPath);
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "brz-bridge-"));
  const outPath = path.join(tmpDir, "converted.brdb");

  try {
    convertBrzToBrdb(inputPath, outPath);

    const db = new Database(outPath, { readonly: true, fileMustExist: true });
    const rows = reconstructBrdbPaths(db);
    db.close();

    const brzPaths = parsed.files.map((file) => file.path).sort();
    const brdbPaths = rows.map((row) => row.path).sort();
    assert.deepEqual(brdbPaths, brzPaths, "BRDB path surface should match BRZ path surface");

    const byPath = new Map(rows.map((row) => [row.path, row]));
    for (const file of parsed.files) {
      const row = byPath.get(file.path);
      assert.ok(row, `Missing file row for ${file.path}`);
      if (file.contentId < 0) {
        continue;
      }
      const blob = parsed.blobs[file.contentId];
      assert.equal(row.compression, blob.compressionMethod, `Compression mismatch for ${file.path}`);
      assert.equal(row.size_uncompressed, blob.decompressedLength, `Uncompressed length mismatch for ${file.path}`);
      assert.equal(row.size_compressed, blob.compressedLength, `Compressed length mismatch for ${file.path}`);
      assert.equal(Buffer.from(row.hash).toString("hex"), blob.hash, `Hash mismatch for ${file.path}`);

      const brdbContent = readBrdbFileContent(row);
      const brzContent = decompressChunk(blob.compressionMethod, blob.data, blob.decompressedLength);
      assert.ok(brdbContent.equals(brzContent), `Content mismatch for ${file.path}`);
    }

    console.log(`PASS ${inputPath}`);
    console.log(`Converted BRDB: ${outPath}`);
    console.log(`files=${parsed.files.length} blobs=${parsed.blobs.length}`);
  } catch (error) {
    console.error(`FAIL ${inputPath}`);
    console.error(error && error.stack ? error.stack : String(error));
    process.exitCode = 1;
  }
}

if (require.main === module) {
  main(process.argv.slice(2));
}
