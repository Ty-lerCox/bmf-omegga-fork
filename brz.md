#### Enums
- EFormatVersion: `uint8`
	- 0: Initial
- ECompressionMethod: `uint8`
	- 0: None
	- 1: Generic zstd
#### Data layout
- BRZ archive:
	1) Archive header: `struct`
	2) Index data: `compressed(struct)`
	3) Blob 0: `compressed(binary)`
	4) Blob 1: `compressed(binary)`
	5) ...
	6) Blob N: `compressed(binary)`
- Archive header:
	1) "BRZ": `uint8 * 3`
	2) Format version:  `EFormatVersion`
	3) Index compression method: `ECompressionMethod`
	4) Index decompressed length: `int32`
	5) Index compressed length: `int32`
	6) Index hash: `uint8[32]`
		- BLAKE3 hash of decompressed index data.
- Index data:
	1) Num folders: `int32`
	2) Num files: `int32`
	3) Num blobs: `int32`
	4) Folder parent ids: `int32 * Num folders`
		- `-1` if folder parent is root.
	5) Folder name lengths: `uint16 * Num folders`
	6) Folder names: `(uint8 * Folder name lengths[i]) * Num folders`
		- Folder names formatted as UTF-8.
	7) File parent ids: `int32 * Num files`
		- `-1` if file parent is root.
	8) File content ids: `int32 * Num files`
		- `-1` if file is empty.
	9) File name lengths: `uint16 * Num files`
	10) File names: `(uint8 * File name lengths[i]) * Num files`
		- File names formatted as UTF-8.
	11) Compression methods: `ECompressionMethod * Num blobs`
	12) Decompressed lengths: `int32 * Num blobs`
	13) Compressed lengths: `int32 * Num blobs`
	14) Blob hashes: `uint8[32] * Blob count`
		- BLAKE3 hash of decompressed blob data.