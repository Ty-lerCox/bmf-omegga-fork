#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const zlib = require("node:zlib");

function usage() {
  console.error(
    [
      "Usage:",
      "  node inspect-brz.js <archive.brz> [--json]",
      "  node inspect-brz.js <archive.brz> --extract <output-dir>",
    ].join("\n")
  );
}

function joinArchivePath(parent, name) {
  return parent ? `${parent}/${name}` : name;
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function parseUtf8Strings(buffer, lengths, offset) {
  const values = [];
  let cursor = offset;
  for (const length of lengths) {
    const next = cursor + length;
    if (next > buffer.length) {
      throw new Error("String table overruns index buffer");
    }
    values.push(buffer.toString("utf8", cursor, next));
    cursor = next;
  }
  return { values, offset: cursor };
}

function parseInt32Array(buffer, count, offset) {
  const values = [];
  let cursor = offset;
  for (let i = 0; i < count; i++) {
    if (cursor + 4 > buffer.length) {
      throw new Error("int32 array overruns index buffer");
    }
    values.push(buffer.readInt32LE(cursor));
    cursor += 4;
  }
  return { values, offset: cursor };
}

function parseUInt16Array(buffer, count, offset) {
  const values = [];
  let cursor = offset;
  for (let i = 0; i < count; i++) {
    if (cursor + 2 > buffer.length) {
      throw new Error("uint16 array overruns index buffer");
    }
    values.push(buffer.readUInt16LE(cursor));
    cursor += 2;
  }
  return { values, offset: cursor };
}

function parseUInt8Array(buffer, count, offset) {
  const end = offset + count;
  if (end > buffer.length) {
    throw new Error("uint8 array overruns index buffer");
  }
  return { values: Array.from(buffer.subarray(offset, end)), offset: end };
}

function buildFolderPaths(names, parentIds) {
  const memo = new Map();
  function resolve(folderId) {
    if (folderId < 0) {
      return "";
    }
    if (memo.has(folderId)) {
      return memo.get(folderId);
    }
    const parentPath = resolve(parentIds[folderId]);
    const folderPath = joinArchivePath(parentPath, names[folderId]);
    memo.set(folderId, folderPath);
    return folderPath;
  }
  return names.map((_, index) => resolve(index));
}

function decompressChunk(compressionMethod, input, expectedSize) {
  if (compressionMethod === 0) {
    return input;
  }
  if (compressionMethod === 1) {
    return zlib.zstdDecompressSync(input, {
      maxOutputLength: expectedSize,
      params: {},
    });
  }
  throw new Error(`Unsupported compression method: ${compressionMethod}`);
}

function parseBrz(archivePath) {
  const data = fs.readFileSync(archivePath);
  if (data.length < 45) {
    throw new Error("Archive is too small to contain a BRZ header");
  }

  const magic = data.toString("ascii", 0, 3);
  if (magic !== "BRZ") {
    throw new Error(`Expected BRZ magic, got ${JSON.stringify(magic)}`);
  }

  const formatVersion = data.readUInt8(3);
  const indexCompressionMethod = data.readUInt8(4);
  const indexDecompressedLength = data.readInt32LE(5);
  const indexCompressedLength = data.readInt32LE(9);
  const indexHash = data.subarray(13, 45);
  const indexOffset = 45;
  const indexEnd = indexOffset + indexCompressedLength;
  if (indexEnd > data.length) {
    throw new Error("Index payload overruns archive length");
  }

  const compressedIndex = data.subarray(indexOffset, indexEnd);
  const indexData = decompressChunk(
    indexCompressionMethod,
    compressedIndex,
    indexDecompressedLength
  );
  if (indexData.length !== indexDecompressedLength) {
    throw new Error(
      `Index length mismatch: expected ${indexDecompressedLength}, got ${indexData.length}`
    );
  }

  let offset = 0;
  const foldersHeader = parseInt32Array(indexData, 3, offset);
  const [numFolders, numFiles, numBlobs] = foldersHeader.values;
  offset = foldersHeader.offset;

  const folderParents = parseInt32Array(indexData, numFolders, offset);
  offset = folderParents.offset;
  const folderNameLengths = parseUInt16Array(indexData, numFolders, offset);
  offset = folderNameLengths.offset;
  const folderNames = parseUtf8Strings(indexData, folderNameLengths.values, offset);
  offset = folderNames.offset;

  const fileParents = parseInt32Array(indexData, numFiles, offset);
  offset = fileParents.offset;
  const fileContentIds = parseInt32Array(indexData, numFiles, offset);
  offset = fileContentIds.offset;
  const fileNameLengths = parseUInt16Array(indexData, numFiles, offset);
  offset = fileNameLengths.offset;
  const fileNames = parseUtf8Strings(indexData, fileNameLengths.values, offset);
  offset = fileNames.offset;

  const compressionMethods = parseUInt8Array(indexData, numBlobs, offset);
  offset = compressionMethods.offset;
  const decompressedLengths = parseInt32Array(indexData, numBlobs, offset);
  offset = decompressedLengths.offset;
  const compressedLengths = parseInt32Array(indexData, numBlobs, offset);
  offset = compressedLengths.offset;

  const blobHashes = [];
  for (let i = 0; i < numBlobs; i++) {
    const end = offset + 32;
    if (end > indexData.length) {
      throw new Error("Blob hash table overruns index buffer");
    }
    blobHashes.push(indexData.subarray(offset, end).toString("hex"));
    offset = end;
  }

  const folderPaths = buildFolderPaths(folderNames.values, folderParents.values);

  const blobs = [];
  let blobOffset = indexEnd;
  for (let i = 0; i < numBlobs; i++) {
    const compressedLength = compressedLengths.values[i];
    const decompressedLength = decompressedLengths.values[i];
    const blobEnd = blobOffset + compressedLength;
    if (blobEnd > data.length) {
      throw new Error(`Blob ${i} overruns archive length`);
    }
    blobs.push({
      id: i,
      compressionMethod: compressionMethods.values[i],
      decompressedLength,
      compressedLength,
      hash: blobHashes[i],
      offset: blobOffset,
      data: data.subarray(blobOffset, blobEnd),
    });
    blobOffset = blobEnd;
  }

  const files = fileNames.values.map((name, index) => {
    const parentId = fileParents.values[index];
    const parentPath = parentId >= 0 ? folderPaths[parentId] : "";
    const archivePathName = joinArchivePath(parentPath, name);
    const contentId = fileContentIds.values[index];
    const blob = contentId >= 0 ? blobs[contentId] : null;
    return {
      id: index,
      name,
      parentId,
      path: archivePathName,
      contentId,
      compressionMethod: blob ? blob.compressionMethod : null,
      compressedLength: blob ? blob.compressedLength : 0,
      decompressedLength: blob ? blob.decompressedLength : 0,
      hash: blob ? blob.hash : null,
    };
  });

  return {
    archivePath,
    header: {
      magic,
      formatVersion,
      indexCompressionMethod,
      indexDecompressedLength,
      indexCompressedLength,
      indexHash: indexHash.toString("hex"),
      archiveLength: data.length,
    },
    index: {
      numFolders,
      numFiles,
      numBlobs,
      folderParents: folderParents.values,
      folderNames: folderNames.values,
      fileParents: fileParents.values,
      fileContentIds: fileContentIds.values,
      fileNames: fileNames.values,
      compressionMethods: compressionMethods.values,
      decompressedLengths: decompressedLengths.values,
      compressedLengths: compressedLengths.values,
      blobHashes,
      parsedLength: offset,
    },
    folders: folderPaths.map((folderPath, index) => ({
      id: index,
      parentId: folderParents.values[index],
      name: folderNames.values[index],
      path: folderPath,
    })),
    files,
    blobs,
  };
}

function extractArchive(parsed, outputDir) {
  ensureDir(outputDir);
  for (const file of parsed.files) {
    if (file.contentId < 0) {
      continue;
    }
    const blob = parsed.blobs[file.contentId];
    const content = decompressChunk(
      blob.compressionMethod,
      blob.data,
      blob.decompressedLength
    );
    const destination = path.join(outputDir, ...file.path.split("/"));
    ensureDir(path.dirname(destination));
    fs.writeFileSync(destination, content);
  }
}

function main(argv) {
  if (argv.length < 1) {
    usage();
    process.exitCode = 1;
    return;
  }

  const archivePath = argv[0];
  const jsonMode = argv.includes("--json");
  const extractFlagIndex = argv.indexOf("--extract");
  const extractDir =
    extractFlagIndex >= 0 && extractFlagIndex + 1 < argv.length
      ? argv[extractFlagIndex + 1]
      : null;

  if (extractFlagIndex >= 0 && !extractDir) {
    usage();
    process.exitCode = 1;
    return;
  }

  const parsed = parseBrz(archivePath);

  if (extractDir) {
    extractArchive(parsed, extractDir);
  }

  if (jsonMode) {
    const serializable = {
      archivePath: parsed.archivePath,
      header: parsed.header,
      folders: parsed.folders,
      files: parsed.files,
    };
    if (extractDir) {
      serializable.extractedTo = path.resolve(extractDir);
    }
    console.log(JSON.stringify(serializable, null, 2));
    return;
  }

  console.log(`Archive: ${parsed.archivePath}`);
  console.log(
    `Header: version=${parsed.header.formatVersion} indexCompression=${parsed.header.indexCompressionMethod} ` +
      `indexDecompressedLength=${parsed.header.indexDecompressedLength} indexCompressedLength=${parsed.header.indexCompressedLength} ` +
      `files=${parsed.index.numFiles} folders=${parsed.index.numFolders} blobs=${parsed.index.numBlobs}`
  );
  for (const file of parsed.files) {
    const content =
      file.contentId >= 0
        ? `blob=${file.contentId} compression=${file.compressionMethod} compressed=${file.compressedLength} decompressed=${file.decompressedLength}`
        : "empty";
    console.log(`${file.path} :: ${content}`);
  }
  if (extractDir) {
    console.log(`Extracted to: ${path.resolve(extractDir)}`);
  }
}

module.exports = {
  parseBrz,
  extractArchive,
  decompressChunk,
};

if (require.main === module) {
  main(process.argv.slice(2));
}
