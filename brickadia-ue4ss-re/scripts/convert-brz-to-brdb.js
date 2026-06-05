#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const Database = require("C:/Users/tycox/OneDrive/Documents/GitHub/Brickadia/omegga-master/omegga-master/node_modules/better-sqlite3");
const { parseBrz } = require("./inspect-brz");

function usage() {
  console.error(
    [
      "Usage:",
      "  node convert-brz-to-brdb.js <input.brz> <output.brdb> [--force]",
    ].join("\n")
  );
}

function ensureParentDir(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function createSchema(db) {
  db.exec(`
    CREATE TABLE blobs (
      blob_id INTEGER PRIMARY KEY,
      compression INTEGER,
      size_uncompressed INTEGER,
      size_compressed INTEGER,
      delta_base_id INTEGER REFERENCES blobs(blob_id),
      hash BLOB,
      content BLOB
    );
    CREATE TABLE folders (
      folder_id INTEGER PRIMARY KEY,
      parent_id INTEGER REFERENCES folders(folder_id),
      name TEXT,
      created_at INTEGER,
      deleted_at INTEGER
    );
    CREATE TABLE files (
      file_id INTEGER PRIMARY KEY,
      parent_id INTEGER REFERENCES folders(folder_id),
      name TEXT,
      content_id INTEGER REFERENCES blobs(blob_id),
      created_at INTEGER,
      deleted_at INTEGER
    );
    CREATE TABLE revisions (
      revision_id INTEGER PRIMARY KEY,
      description TEXT,
      created_at INTEGER
    );
  `);
}

function convertBrzToBrdb(inputPath, outputPath) {
  const parsed = parseBrz(inputPath);
  ensureParentDir(outputPath);
  if (fs.existsSync(outputPath)) {
    fs.unlinkSync(outputPath);
  }

  const db = new Database(outputPath);
  try {
    createSchema(db);
    const insertFolder = db.prepare(
      "INSERT INTO folders (folder_id, parent_id, name, created_at, deleted_at) VALUES (?, ?, ?, ?, ?)"
    );
    const insertFile = db.prepare(
      "INSERT INTO files (file_id, parent_id, name, content_id, created_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?)"
    );
    const insertBlob = db.prepare(
      "INSERT INTO blobs (blob_id, compression, size_uncompressed, size_compressed, delta_base_id, hash, content) VALUES (?, ?, ?, ?, ?, ?, ?)"
    );
    const insertRevision = db.prepare(
      "INSERT INTO revisions (revision_id, description, created_at) VALUES (?, ?, ?)"
    );

    const folderIdMap = new Map();
    const blobIdMap = new Map();

    const tx = db.transaction(() => {
      insertRevision.run(1, "Imported from BRZ", 0);

      for (const folder of parsed.folders) {
        const folderId = folder.id + 1;
        folderIdMap.set(folder.id, folderId);
        const parentId =
          folder.parentId >= 0 ? folderIdMap.get(folder.parentId) : null;
        insertFolder.run(folderId, parentId, folder.name, 0, null);
      }

      for (const blob of parsed.blobs) {
        const blobId = blob.id + 1;
        blobIdMap.set(blob.id, blobId);
        insertBlob.run(
          blobId,
          blob.compressionMethod,
          blob.decompressedLength,
          blob.compressedLength,
          null,
          Buffer.from(blob.hash, "hex"),
          blob.data
        );
      }

      for (const file of parsed.files) {
        const fileId = file.id + 1;
        const parentId =
          file.parentId >= 0 ? folderIdMap.get(file.parentId) : null;
        const contentId =
          file.contentId >= 0 ? blobIdMap.get(file.contentId) : null;
        insertFile.run(fileId, parentId, file.name, contentId, 0, null);
      }
    });

    tx();
  } finally {
    db.close();
  }

  return parsed;
}

function main(argv) {
  if (argv.length < 2) {
    usage();
    process.exitCode = 1;
    return;
  }

  const inputPath = argv[0];
  const outputPath = argv[1];
  const force = argv.includes("--force");

  if (fs.existsSync(outputPath) && !force) {
    console.error(`Refusing to overwrite existing file: ${outputPath}`);
    process.exitCode = 1;
    return;
  }

  const parsed = convertBrzToBrdb(inputPath, outputPath);
  console.log(`Converted: ${inputPath}`);
  console.log(`Output: ${outputPath}`);
  console.log(
    `folders=${parsed.folders.length} files=${parsed.files.length} blobs=${parsed.blobs.length}`
  );
}

module.exports = {
  convertBrzToBrdb,
};

if (require.main === module) {
  main(process.argv.slice(2));
}
