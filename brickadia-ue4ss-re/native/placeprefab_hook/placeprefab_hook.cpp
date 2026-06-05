#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <atomic>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <intrin.h>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr uintptr_t kImageBase = 0x140000000ull;
constexpr uintptr_t kOuterAdditiveLoadVa = 0x14472CBD0ull;
constexpr uintptr_t kAdditiveLoadVa = 0x14472D050ull;
constexpr uintptr_t kActionSubmitterVa = 0x1448A5880ull;
constexpr uintptr_t kSharedSubmitVa = 0x1443DF4F0ull;
constexpr uintptr_t kTargetAllocatorVa = 0x144796F00ull;
constexpr uintptr_t kRawPrefabCacheVa = 0x14437FB00ull;
constexpr uintptr_t kEntityMutationDescriptorVa = 0x146C79300ull;
constexpr uintptr_t kEntityPlacementDescriptorVa = 0x146C790E0ull;
constexpr uintptr_t kPlacePrefabDescriptorVa = 0x146C79D50ull;
constexpr uintptr_t kOuterAdditiveLoadRva = kOuterAdditiveLoadVa - kImageBase;
constexpr uintptr_t kAdditiveLoadRva = kAdditiveLoadVa - kImageBase;
constexpr uintptr_t kActionSubmitterRva = kActionSubmitterVa - kImageBase;
constexpr uintptr_t kSharedSubmitRva = kSharedSubmitVa - kImageBase;
constexpr uintptr_t kTargetAllocatorRva = kTargetAllocatorVa - kImageBase;
constexpr uintptr_t kRawPrefabCacheRva = kRawPrefabCacheVa - kImageBase;
constexpr uintptr_t kEntityMutationDescriptorRva = kEntityMutationDescriptorVa - kImageBase;
constexpr uintptr_t kEntityPlacementDescriptorRva = kEntityPlacementDescriptorVa - kImageBase;
constexpr uintptr_t kPlacePrefabDescriptorRva = kPlacePrefabDescriptorVa - kImageBase;
constexpr size_t kPatchLen = 16;
constexpr size_t kActionPatchLen = 19;
constexpr size_t kSharedPatchLen = 17;
constexpr size_t kTargetAllocatorPatchLen = 14;
constexpr size_t kAbsoluteJumpLen = 13;
constexpr int32_t kDefaultYOffset = 260;
constexpr long kDefaultDuplicateLimit = 12;
constexpr size_t kParamsSize = 0x28;
constexpr size_t kContextCopySize = 0x200;
constexpr size_t kActionParamCopySize = 0x200;
constexpr size_t kSharedQueueCopySize = 0x100;
constexpr size_t kSharedBlockCopySize = 0x8000;
constexpr uint16_t kSharedNodeScanLimit = 512;

const unsigned char kExpectedPrologue[kPatchLen] = {
    0x41, 0x57,                         // push r15
    0x41, 0x56,                         // push r14
    0x41, 0x54,                         // push r12
    0x56,                               // push rsi
    0x57,                               // push rdi
    0x53,                               // push rbx
    0x48, 0x81, 0xEC, 0x88, 0x06, 0x00, 0x00 // sub rsp,688h
};

const unsigned char kExpectedActionPrologue[kActionPatchLen] = {
    0x41, 0x57,                         // push r15
    0x41, 0x56,                         // push r14
    0x41, 0x55,                         // push r13
    0x41, 0x54,                         // push r12
    0x56,                               // push rsi
    0x57,                               // push rdi
    0x55,                               // push rbp
    0x53,                               // push rbx
    0x48, 0x81, 0xEC, 0x98, 0x03, 0x00, 0x00 // sub rsp,398h
};

const unsigned char kExpectedSharedPrologue[kSharedPatchLen] = {
    0x41, 0x57,                         // push r15
    0x41, 0x56,                         // push r14
    0x41, 0x54,                         // push r12
    0x56,                               // push rsi
    0x57,                               // push rdi
    0x55,                               // push rbp
    0x53,                               // push rbx
    0x48, 0x81, 0xEC, 0xC0, 0x00, 0x00, 0x00 // sub rsp,0c0h
};

const unsigned char kExpectedTargetAllocatorPrologue[kTargetAllocatorPatchLen] = {
    0x48, 0x89, 0xD0,                   // mov rax,rdx
    0x8B, 0x51, 0x40,                   // mov edx,dword ptr [rcx+40h]
    0x44, 0x8D, 0x42, 0x01,             // lea r8d,[rdx+1]
    0x44, 0x89, 0x41, 0x40              // mov dword ptr [rcx+40h],r8d
};

const wchar_t* kLogPath = L"C:\\Users\\tycox\\OneDrive\\Documents\\GitHub\\Brickadia\\brickadia-ue4ss-re\\artifacts\\placeprefab-native-hook.log";
const wchar_t* kControlPath = L"C:\\Users\\tycox\\OneDrive\\Documents\\GitHub\\Brickadia\\brickadia-ue4ss-re\\artifacts\\placeprefab-native-hook-control.txt";
const wchar_t* kCommandPath = L"C:\\Users\\tycox\\OneDrive\\Documents\\GitHub\\Brickadia\\brickadia-ue4ss-re\\artifacts\\placeprefab-native-hook-outer-command.txt";
const wchar_t* kStatusPath = L"C:\\Users\\tycox\\OneDrive\\Documents\\GitHub\\Brickadia\\brickadia-ue4ss-re\\artifacts\\placeprefab-native-hook-outer-status.txt";
const wchar_t* kSharedTemplatePath = L"C:\\Users\\tycox\\OneDrive\\Documents\\GitHub\\Brickadia\\brickadia-ue4ss-re\\artifacts\\placeprefab-shared-template.bin";

using AdditiveLoadFn = void*(__fastcall*)(void* manager, void* out_result, void* bundle_or_archive, void* params, void* context);
using OuterAdditiveLoadFn = void(__fastcall*)(void* manager, void* bundle_or_archive, void* params, void* scratch);
using ActionSubmitterFn = void(__fastcall*)(void* owner, void* request, void* placement);
using SharedSubmitFn = uint64_t(__fastcall*)(void* owner, void* queue, uint64_t arg2, uint64_t arg3);
using TargetAllocatorFn = void(__fastcall*)(void* registry, int32_t* out_id);
using RawPrefabCacheFn = void(__fastcall*)(void* cache_owner, void* raw_buffer_and_len, void* callback_state);
using HookEngineTickFn = void(__cdecl*)();
using RegisterEngineTickPostCallbackFn = void(__cdecl*)(std::function<void(void*, float)>);

AdditiveLoadFn g_original = nullptr;
OuterAdditiveLoadFn g_outer_additive = nullptr;
ActionSubmitterFn g_original_action = nullptr;
SharedSubmitFn g_original_shared = nullptr;
TargetAllocatorFn g_original_target_allocator = nullptr;
void* g_trampoline = nullptr;
void* g_action_trampoline = nullptr;
void* g_shared_trampoline = nullptr;
void* g_target_allocator_trampoline = nullptr;
uintptr_t g_module_base = 0;
std::atomic<bool> g_installed{false};
std::atomic<bool> g_action_installed{false};
std::atomic<bool> g_shared_installed{false};
std::atomic<bool> g_target_allocator_installed{false};
std::atomic<bool> g_tick_registered{false};
std::atomic<long> g_hits{0};
std::atomic<long> g_action_hits{0};
std::atomic<long> g_shared_hits{0};
std::atomic<long> g_target_allocator_hits{0};
std::atomic<long> g_duplicates{0};
std::atomic<int32_t> g_next_synthetic_target_id{2};

struct AdditiveSnapshot {
    bool has = false;
    void* manager = nullptr;
    void* bundle_or_archive = nullptr;
    void* context_original = nullptr;
    unsigned char params[kParamsSize]{};
    unsigned char context[kContextCopySize]{};
};

struct ActionSnapshot {
    bool has = false;
    void* owner = nullptr;
    void* request_original = nullptr;
    void* placement_original = nullptr;
    unsigned char request[kActionParamCopySize]{};
    unsigned char placement[kActionParamCopySize]{};
};

struct SharedSnapshot {
    bool has = false;
    void* owner = nullptr;
    void* queue_original = nullptr;
    void* block_original = nullptr;
    uint64_t arg2 = 0;
    uint64_t arg3 = 0;
    uint16_t block_cursor = 0;
    uint16_t block_count = 0;
    uint16_t place_node_offset = 0;
    uint16_t entity_node_offset = 0;
    void* target_registry = nullptr;
    int32_t target_id = -1;
    int32_t source_x = 0;
    int32_t source_y = 0;
    int32_t source_z = 0;
    uint64_t captured_place_desc = 0;
    uint64_t captured_entity_desc = 0;
    uint64_t captured_entity_mutation_desc = 0;
    unsigned char queue[kSharedQueueCopySize]{};
    unsigned char block[kSharedBlockCopySize]{};
};

struct SharedTemplateHeader {
    char magic[8]{};
    uint32_t version = 0;
    uint32_t queue_size = 0;
    uint32_t block_size = 0;
    uint64_t arg2 = 0;
    uint64_t arg3 = 0;
    uint64_t captured_place_desc = 0;
    uint64_t captured_entity_desc = 0;
    uint64_t captured_entity_mutation_desc = 0;
    uint16_t block_cursor = 0;
    uint16_t block_count = 0;
    uint16_t place_node_offset = 0;
    uint16_t entity_node_offset = 0;
    int32_t target_id = -1;
    int32_t source_x = 0;
    int32_t source_y = 0;
    int32_t source_z = 0;
};

std::mutex g_snapshot_mutex;
AdditiveSnapshot g_latest_global;
ActionSnapshot g_latest_action;
SharedSnapshot g_latest_shared;
void* g_latest_target_registry = nullptr;
int32_t g_latest_target_id = -1;
uint64_t g_last_tick_poll_ms = 0;
std::string g_last_command_nonce;
std::string g_file_prefab_path;
void* g_file_prefab_entry = nullptr;
uint64_t g_file_prefab_hash_qwords[4]{};
bool g_file_prefab_hash_valid = false;
std::string g_file_prefab_pending_path;
uint64_t g_file_prefab_pending_hash_qwords[4]{};
bool g_file_prefab_pending_hash_valid = false;
DWORD g_file_prefab_pending_started_ms = 0;
thread_local bool g_replay_in_progress = false;
thread_local bool g_action_replay_in_progress = false;
thread_local bool g_shared_replay_in_progress = false;
thread_local long g_replay_additive_hits = 0;
thread_local DWORD g_last_shared_exception_code = 0;
thread_local void* g_last_shared_exception_address = nullptr;
thread_local void* g_last_shared_exception_rcx = nullptr;
thread_local void* g_last_shared_exception_rdx = nullptr;
thread_local void* g_last_shared_exception_r8 = nullptr;
thread_local void* g_last_shared_exception_r9 = nullptr;
thread_local void* g_last_shared_exception_rsp = nullptr;

void remember_file_prefab_entry(
    const char* reason,
    const std::string& path,
    void* entry,
    const uint64_t* hash_qwords);

void advance_synthetic_target_floor(int32_t next_id) {
    if (next_id < 2) {
        return;
    }

    int32_t current = g_next_synthetic_target_id.load();
    while (current < next_id &&
           !g_next_synthetic_target_id.compare_exchange_weak(current, next_id)) {
    }
}

int32_t reserve_synthetic_target_id() {
    int32_t id = g_next_synthetic_target_id.fetch_add(1);
    if (id < 2) {
        advance_synthetic_target_floor(2);
        id = g_next_synthetic_target_id.fetch_add(1);
    }
    return id;
}

void log_line(const char* fmt, ...) {
    FILE* file = nullptr;
    _wfopen_s(&file, kLogPath, L"ab");
    if (!file) {
        return;
    }

    SYSTEMTIME st{};
    GetLocalTime(&st);
    std::fprintf(
        file,
        "%04u-%02u-%02u %02u:%02u:%02u.%03u ",
        st.wYear,
        st.wMonth,
        st.wDay,
        st.wHour,
        st.wMinute,
        st.wSecond,
        st.wMilliseconds);

    va_list args;
    va_start(args, fmt);
    std::vfprintf(file, fmt, args);
    va_end(args);

    std::fprintf(file, "\n");
    std::fclose(file);
}

bool safe_copy(void* dst, const void* src, size_t len) {
    if (!src) {
        std::memset(dst, 0, len);
        return false;
    }

    __try {
        std::memcpy(dst, src, len);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        std::memset(dst, 0, len);
        return false;
    }
}

void write_status(const char* fmt, ...) {
    FILE* file = nullptr;
    _wfopen_s(&file, kStatusPath, L"wb");
    if (!file) {
        return;
    }

    va_list args;
    va_start(args, fmt);
    std::vfprintf(file, fmt, args);
    va_end(args);

    std::fprintf(file, "\n");
    std::fclose(file);
}

uint8_t safe_read_u8(const void* ptr, size_t offset, uint8_t fallback = 0) {
    if (!ptr) {
        return fallback;
    }

    __try {
        return *(reinterpret_cast<const uint8_t*>(ptr) + offset);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return fallback;
    }
}

bool is_writable_memory(void* ptr, size_t len) {
    if (!ptr || len == 0) {
        return false;
    }

    MEMORY_BASIC_INFORMATION mbi{};
    if (!VirtualQuery(ptr, &mbi, sizeof(mbi))) {
        return false;
    }

    if (mbi.State != MEM_COMMIT || (mbi.Protect & (PAGE_GUARD | PAGE_NOACCESS)) != 0) {
        return false;
    }

    const DWORD writable =
        PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY;
    if ((mbi.Protect & writable) == 0) {
        return false;
    }

    const auto start = reinterpret_cast<uintptr_t>(ptr);
    const auto region_start = reinterpret_cast<uintptr_t>(mbi.BaseAddress);
    const auto region_end = region_start + mbi.RegionSize;
    return start >= region_start && start + len >= start && start + len <= region_end;
}

bool emulate_target_allocator(void* registry, int32_t* out_id, int32_t* id_out, int32_t* next_id_out) {
    if (!registry || !out_id || !id_out || !next_id_out) {
        return false;
    }

    auto* next_ptr = static_cast<unsigned char*>(registry) + 0x40;
    if (!is_writable_memory(next_ptr, sizeof(int32_t)) || !is_writable_memory(out_id, sizeof(int32_t))) {
        return false;
    }

    __try {
        int32_t id = *reinterpret_cast<int32_t*>(next_ptr);
        *reinterpret_cast<int32_t*>(next_ptr) = id + 1;
        *out_id = id;
        *id_out = id;
        *next_id_out = id + 1;
        advance_synthetic_target_floor(id + 1);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

int32_t read_i32(const unsigned char* bytes, size_t offset) {
    int32_t value = 0;
    std::memcpy(&value, bytes + offset, sizeof(value));
    return value;
}

uint64_t read_u64(const unsigned char* bytes, size_t offset) {
    uint64_t value = 0;
    std::memcpy(&value, bytes + offset, sizeof(value));
    return value;
}

uint16_t read_u16(const unsigned char* bytes, size_t offset) {
    uint16_t value = 0;
    std::memcpy(&value, bytes + offset, sizeof(value));
    return value;
}

uint32_t read_u32(const unsigned char* bytes, size_t offset) {
    uint32_t value = 0;
    std::memcpy(&value, bytes + offset, sizeof(value));
    return value;
}

double read_f64(const unsigned char* bytes, size_t offset) {
    double value = 0.0;
    std::memcpy(&value, bytes + offset, sizeof(value));
    return value;
}

void write_i32(unsigned char* bytes, size_t offset, int32_t value) {
    std::memcpy(bytes + offset, &value, sizeof(value));
}

void write_u16(unsigned char* bytes, size_t offset, uint16_t value) {
    std::memcpy(bytes + offset, &value, sizeof(value));
}

void write_u32(unsigned char* bytes, size_t offset, uint32_t value) {
    std::memcpy(bytes + offset, &value, sizeof(value));
}

void write_u64(unsigned char* bytes, size_t offset, uint64_t value) {
    std::memcpy(bytes + offset, &value, sizeof(value));
}

void write_f64(unsigned char* bytes, size_t offset, double value) {
    std::memcpy(bytes + offset, &value, sizeof(value));
}

void prepare_shared_queue_for_replay(unsigned char* queue, unsigned char* block, int32_t block_count) {
    if (!queue) {
        return;
    }

    // q28/q30 is a ref-counted auxiliary pointer in captured queues; disk templates carry stale process addresses.
    write_u64(queue, 0x28, 0);
    write_u64(queue, 0x30, 0);
    write_u64(queue, 0x40, reinterpret_cast<uint64_t>(block));
    write_u64(queue, 0x48, reinterpret_cast<uint64_t>(block));
    write_u16(queue, 0x58, 0);
    write_u16(queue, 0x5A, 0);
    write_i32(queue, 0x5C, 1);
    write_i32(queue, 0x60, block_count);
}

bool safe_read_i32_mem(const void* base, size_t offset, int32_t* value_out);
bool safe_read_u32_mem(const void* base, size_t offset, uint32_t* value_out);
bool safe_read_u64_mem(const void* base, size_t offset, uint64_t* value_out);
void log_prefab_entry_fields(const char* prefix, const char* context, void* entry);

uintptr_t runtime_place_prefab_descriptor() {
    return g_module_base ? g_module_base + kPlacePrefabDescriptorRva : kPlacePrefabDescriptorVa;
}

uintptr_t runtime_entity_mutation_descriptor() {
    return g_module_base ? g_module_base + kEntityMutationDescriptorRva : kEntityMutationDescriptorVa;
}

uintptr_t runtime_entity_placement_descriptor() {
    return g_module_base ? g_module_base + kEntityPlacementDescriptorRva : kEntityPlacementDescriptorVa;
}

RawPrefabCacheFn runtime_raw_prefab_cache() {
    return reinterpret_cast<RawPrefabCacheFn>(g_module_base ? g_module_base + kRawPrefabCacheRva : kRawPrefabCacheVa);
}

bool looks_like_action_descriptor(uint64_t descriptor) {
    const uintptr_t base = g_module_base ? g_module_base : kImageBase;
    return descriptor >= base + 0x6C70000ull && descriptor < base + 0x6CA0000ull;
}

const char* descriptor_label(uint64_t descriptor) {
    if (descriptor == runtime_place_prefab_descriptor()) {
        return "place_prefab";
    }
    if (descriptor == runtime_entity_mutation_descriptor()) {
        return "entity_mutation";
    }
    if (descriptor == runtime_entity_placement_descriptor()) {
        return "entity_place";
    }
    return "other";
}

bool shared_node_offset_by_index(
    const unsigned char* block,
    size_t block_size,
    uint16_t index,
    uint16_t* entry_offset_out,
    uint16_t* node_offset_out) {
    if (!block || block_size < 0x20) {
        return false;
    }

    const uint16_t capacity = read_u16(block, 0x10);
    const uint16_t count = read_u16(block, 0x14);
    if (index >= count) {
        return false;
    }

    const size_t entry_pos = 0x18u + static_cast<size_t>(capacity) - (static_cast<size_t>(index) + 1u) * 2u;
    if (entry_pos + sizeof(uint16_t) > block_size) {
        return false;
    }

    const uint16_t entry_offset = read_u16(block, entry_pos);
    const size_t node_offset = 0x18u + static_cast<size_t>(entry_offset);
    if (node_offset + sizeof(uint64_t) > block_size || node_offset > 0xffffu) {
        return false;
    }

    *entry_offset_out = entry_offset;
    *node_offset_out = static_cast<uint16_t>(node_offset);
    return true;
}

bool find_place_prefab_node_offset(
    const unsigned char* block,
    size_t block_size,
    uint16_t* node_offset_out,
    uint16_t* entry_offset_out) {
    const uintptr_t place_desc = runtime_place_prefab_descriptor();
    const uint16_t count = block && block_size >= 0x16 ? read_u16(block, 0x14) : 0;
    const uint16_t limit = count > kSharedNodeScanLimit ? kSharedNodeScanLimit : count;
    for (uint16_t i = 0; i < limit; ++i) {
        uint16_t entry_offset = 0;
        uint16_t node_offset = 0;
        if (!shared_node_offset_by_index(block, block_size, i, &entry_offset, &node_offset)) {
            continue;
        }
        if (static_cast<size_t>(node_offset) + 0x30 <= block_size && read_u64(block, node_offset) == place_desc) {
            *node_offset_out = node_offset;
            *entry_offset_out = entry_offset;
            return true;
        }
    }

    const uint16_t cursor = block && block_size >= 0x14 ? read_u16(block, 0x12) : 0;
    if (cursor >= 0x18) {
        const uint16_t fallback_offset = static_cast<uint16_t>(cursor - 0x18);
        if (static_cast<size_t>(fallback_offset) + 0x30 <= block_size &&
            read_u64(block, fallback_offset) == place_desc) {
            *node_offset_out = fallback_offset;
            *entry_offset_out = 0;
            return true;
        }
    }

    return false;
}

bool patch_entity_vector(
    unsigned char* block,
    uint16_t node_offset,
    size_t relative_offset,
    bool has_absolute,
    int32_t spawn_x,
    int32_t spawn_y,
    int32_t spawn_z,
    int32_t delta_x,
    int32_t delta_y,
    int32_t delta_z) {
    const size_t vector_offset = static_cast<size_t>(node_offset) + relative_offset;
    if (!block || vector_offset + 0x18 > kSharedBlockCopySize) {
        return false;
    }

    const double old_x = read_f64(block, vector_offset + 0x00);
    const double old_y = read_f64(block, vector_offset + 0x08);
    const double old_z = read_f64(block, vector_offset + 0x10);
    const double new_x = has_absolute ? static_cast<double>(spawn_x) : old_x + static_cast<double>(delta_x);
    const double new_y = has_absolute ? static_cast<double>(spawn_y) : old_y + static_cast<double>(delta_y);
    const double new_z = has_absolute ? static_cast<double>(spawn_z) : old_z + static_cast<double>(delta_z);

    write_f64(block, vector_offset + 0x00, new_x);
    write_f64(block, vector_offset + 0x08, new_y);
    write_f64(block, vector_offset + 0x10, new_z);
    return true;
}

void log_shared_nodes(const char* prefix, long hit, const unsigned char* block, uintptr_t block_ptr) {
    if (!block) {
        return;
    }

    const uint16_t count = read_u16(block, 0x14);
    const uint16_t limit = count > 32 ? 32 : count;
    for (uint16_t i = 0; i < limit; ++i) {
        uint16_t entry_offset = 0;
        uint16_t node_offset = 0;
        if (!shared_node_offset_by_index(block, kSharedBlockCopySize, i, &entry_offset, &node_offset)) {
            continue;
        }
        if (static_cast<size_t>(node_offset) + 0x30 > kSharedBlockCopySize) {
            continue;
        }

        const uint64_t desc = read_u64(block, node_offset + 0x00);
        const bool has_entity_transform =
            desc == runtime_entity_placement_descriptor() &&
            static_cast<size_t>(node_offset) + 0xB0 <= kSharedBlockCopySize;
        const double tf_x = has_entity_transform ? read_f64(block, node_offset + 0x50) : 0.0;
        const double tf_y = has_entity_transform ? read_f64(block, node_offset + 0x58) : 0.0;
        const double tf_z = has_entity_transform ? read_f64(block, node_offset + 0x60) : 0.0;
        const int32_t b0 = static_cast<size_t>(node_offset) + 0xB4 <= kSharedBlockCopySize
            ? read_i32(block, node_offset + 0xB0)
            : 0;
        const int32_t b4 = static_cast<size_t>(node_offset) + 0xB8 <= kSharedBlockCopySize
            ? read_i32(block, node_offset + 0xB4)
            : 0;

        log_line(
            "%s_node hit=%ld index=%u entry=0x%X node=%p node_off=0x%X kind=%s desc=%p q08=%p target_id=%u q18=%p pos=%d,%d,%d orient=%u entity_tf=%.2f,%.2f,%.2f b0=%d b4=%d",
            prefix ? prefix : "shared",
            hit,
            static_cast<unsigned>(i),
            static_cast<unsigned>(entry_offset),
            reinterpret_cast<void*>(block_ptr + node_offset),
            static_cast<unsigned>(node_offset),
            descriptor_label(desc),
            reinterpret_cast<void*>(desc),
            reinterpret_cast<void*>(read_u64(block, node_offset + 0x08)),
            static_cast<unsigned>(read_u32(block, node_offset + 0x10)),
            reinterpret_cast<void*>(read_u64(block, node_offset + 0x18)),
            read_i32(block, node_offset + 0x20),
            read_i32(block, node_offset + 0x24),
            read_i32(block, node_offset + 0x28),
            static_cast<unsigned>(block[node_offset + 0x2C]),
            tf_x,
            tf_y,
            tf_z,
            b0,
            b4);

        if (desc == runtime_place_prefab_descriptor()) {
            void* prefab_entry = reinterpret_cast<void*>(read_u64(block, node_offset + 0x18));
            log_prefab_entry_fields(prefix ? prefix : "shared", "place_node_q18", prefab_entry);
        }
    }
}

void log_prefab_entry_fields(const char* prefix, const char* context, void* entry) {
    if (!entry) {
        log_line(
            "prefab_entry_fields prefix=%s context=%s entry=%p missing=1",
            prefix ? prefix : "",
            context ? context : "",
            entry);
        return;
    }

    uint64_t q00 = 0;
    uint64_t q08 = 0;
    uint64_t q10 = 0;
    uint64_t q18 = 0;
    uint64_t q20 = 0;
    uint64_t q28 = 0;
    uint64_t q30 = 0;
    uint64_t q38 = 0;
    uint64_t q40 = 0;
    uint64_t q48 = 0;
    uint64_t qf0 = 0;
    uint64_t qf8 = 0;
    uint64_t q1e8 = 0;
    uint64_t q1f0 = 0;
    uint64_t q1f8 = 0;
    int32_t ibc = 0;
    int32_t ic0 = 0;
    safe_read_u64_mem(entry, 0x00, &q00);
    safe_read_u64_mem(entry, 0x08, &q08);
    safe_read_u64_mem(entry, 0x10, &q10);
    safe_read_u64_mem(entry, 0x18, &q18);
    safe_read_u64_mem(entry, 0x20, &q20);
    safe_read_u64_mem(entry, 0x28, &q28);
    safe_read_u64_mem(entry, 0x30, &q30);
    safe_read_u64_mem(entry, 0x38, &q38);
    safe_read_u64_mem(entry, 0x40, &q40);
    safe_read_u64_mem(entry, 0x48, &q48);
    safe_read_i32_mem(entry, 0xBC, &ibc);
    safe_read_i32_mem(entry, 0xC0, &ic0);
    safe_read_u64_mem(entry, 0xF0, &qf0);
    safe_read_u64_mem(entry, 0xF8, &qf8);
    safe_read_u64_mem(entry, 0x1E8, &q1e8);
    safe_read_u64_mem(entry, 0x1F0, &q1f0);
    safe_read_u64_mem(entry, 0x1F8, &q1f8);

    log_line(
        "prefab_entry_fields prefix=%s context=%s entry=%p q00=%p q08=%p q10=%p q18=%p q20=%p q28=%p q30=%p q38=%p q40=%p q48=%p ibc=%d ic0=%d qf0=%p qf8=%p q1e8=%p q1f0=%p q1f8=%p",
        prefix ? prefix : "",
        context ? context : "",
        entry,
        reinterpret_cast<void*>(q00),
        reinterpret_cast<void*>(q08),
        reinterpret_cast<void*>(q10),
        reinterpret_cast<void*>(q18),
        reinterpret_cast<void*>(q20),
        reinterpret_cast<void*>(q28),
        reinterpret_cast<void*>(q30),
        reinterpret_cast<void*>(q38),
        reinterpret_cast<void*>(q40),
        reinterpret_cast<void*>(q48),
        ibc,
        ic0,
        reinterpret_cast<void*>(qf0),
        reinterpret_cast<void*>(qf8),
        reinterpret_cast<void*>(q1e8),
        reinterpret_cast<void*>(q1f0),
        reinterpret_cast<void*>(q1f8));
}

bool find_entity_placement_node_offset(
    const unsigned char* block,
    size_t block_size,
    uint16_t* node_offset_out,
    uint16_t* entry_offset_out) {
    const uintptr_t entity_desc = runtime_entity_placement_descriptor();
    const uint16_t count = block && block_size >= 0x16 ? read_u16(block, 0x14) : 0;
    const uint16_t limit = count > kSharedNodeScanLimit ? kSharedNodeScanLimit : count;
    for (uint16_t i = 0; i < limit; ++i) {
        uint16_t entry_offset = 0;
        uint16_t node_offset = 0;
        if (!shared_node_offset_by_index(block, block_size, i, &entry_offset, &node_offset)) {
            continue;
        }
        if (static_cast<size_t>(node_offset) + 0x30 <= block_size &&
            read_u64(block, node_offset) == entity_desc) {
            if (node_offset_out) {
                *node_offset_out = node_offset;
            }
            if (entry_offset_out) {
                *entry_offset_out = entry_offset;
            }
            return true;
        }
    }

    return false;
}

void patch_shared_block_runtime_descriptors(unsigned char* block, const SharedSnapshot& snapshot) {
    if (!block) {
        return;
    }

    const uint16_t count = read_u16(block, 0x14);
    const uint16_t limit = count > kSharedNodeScanLimit ? kSharedNodeScanLimit : count;
    for (uint16_t i = 0; i < limit; ++i) {
        uint16_t entry_offset = 0;
        uint16_t node_offset = 0;
        if (!shared_node_offset_by_index(block, kSharedBlockCopySize, i, &entry_offset, &node_offset)) {
            continue;
        }
        if (static_cast<size_t>(node_offset) + 0x30 > kSharedBlockCopySize) {
            continue;
        }

        const uint64_t descriptor = read_u64(block, node_offset);
        if (node_offset == snapshot.place_node_offset ||
            (snapshot.captured_place_desc != 0 && descriptor == snapshot.captured_place_desc)) {
            write_u64(block, node_offset, runtime_place_prefab_descriptor());
        } else if (node_offset == snapshot.entity_node_offset ||
                   (snapshot.captured_entity_desc != 0 && descriptor == snapshot.captured_entity_desc)) {
            write_u64(block, node_offset, runtime_entity_placement_descriptor());
        } else if (snapshot.captured_entity_mutation_desc != 0 &&
                   descriptor == snapshot.captured_entity_mutation_desc) {
            write_u64(block, node_offset, runtime_entity_mutation_descriptor());
        }
    }
}

void persist_shared_template(const SharedSnapshot& snapshot) {
    if (!snapshot.has || snapshot.place_node_offset == 0 || snapshot.block_count == 0) {
        return;
    }

    FILE* file = nullptr;
    _wfopen_s(&file, kSharedTemplatePath, L"wb");
    if (!file) {
        log_line("shared_template_persist_failed open path=%S", kSharedTemplatePath);
        return;
    }

    SharedTemplateHeader header{};
    const char magic[8] = {'B', 'R', 'S', 'H', 'T', 'P', 'L', '1'};
    std::memcpy(header.magic, magic, sizeof(header.magic));
    header.version = 1;
    header.queue_size = static_cast<uint32_t>(kSharedQueueCopySize);
    header.block_size = static_cast<uint32_t>(kSharedBlockCopySize);
    header.arg2 = snapshot.arg2;
    header.arg3 = snapshot.arg3;
    header.captured_place_desc = snapshot.captured_place_desc;
    header.captured_entity_desc = snapshot.captured_entity_desc;
    header.captured_entity_mutation_desc = snapshot.captured_entity_mutation_desc;
    header.block_cursor = snapshot.block_cursor;
    header.block_count = snapshot.block_count;
    header.place_node_offset = snapshot.place_node_offset;
    header.entity_node_offset = snapshot.entity_node_offset;
    header.target_id = snapshot.target_id;
    header.source_x = snapshot.source_x;
    header.source_y = snapshot.source_y;
    header.source_z = snapshot.source_z;

    const bool ok =
        std::fwrite(&header, 1, sizeof(header), file) == sizeof(header) &&
        std::fwrite(snapshot.queue, 1, kSharedQueueCopySize, file) == kSharedQueueCopySize &&
        std::fwrite(snapshot.block, 1, kSharedBlockCopySize, file) == kSharedBlockCopySize;
    std::fclose(file);

    log_line(
        "shared_template_persisted ok=%d path=%S cursor=%u count=%u place_node=0x%X entity_node=0x%X target_id=%d source=%d,%d,%d",
        ok ? 1 : 0,
        kSharedTemplatePath,
        static_cast<unsigned>(snapshot.block_cursor),
        static_cast<unsigned>(snapshot.block_count),
        static_cast<unsigned>(snapshot.place_node_offset),
        static_cast<unsigned>(snapshot.entity_node_offset),
        snapshot.target_id,
        snapshot.source_x,
        snapshot.source_y,
        snapshot.source_z);
}

bool load_shared_template_from_disk(SharedSnapshot* snapshot_out) {
    if (!snapshot_out) {
        return false;
    }

    FILE* file = nullptr;
    _wfopen_s(&file, kSharedTemplatePath, L"rb");
    if (!file) {
        return false;
    }

    SharedTemplateHeader header{};
    const char magic[8] = {'B', 'R', 'S', 'H', 'T', 'P', 'L', '1'};
    const bool header_ok =
        std::fread(&header, 1, sizeof(header), file) == sizeof(header) &&
        std::memcmp(header.magic, magic, sizeof(header.magic)) == 0 &&
        header.version == 1 &&
        header.queue_size == kSharedQueueCopySize &&
        header.block_size == kSharedBlockCopySize &&
        header.place_node_offset != 0 &&
        static_cast<size_t>(header.place_node_offset) + 0x30 <= kSharedBlockCopySize &&
        header.block_count > 0 &&
        header.block_count <= 512;
    if (!header_ok) {
        std::fclose(file);
        log_line(
            "shared_template_load_failed invalid_header path=%S version=%u queue=%u block=%u place=0x%X count=%u",
            kSharedTemplatePath,
            header.version,
            header.queue_size,
            header.block_size,
            static_cast<unsigned>(header.place_node_offset),
            static_cast<unsigned>(header.block_count));
        return false;
    }

    SharedSnapshot snapshot{};
    snapshot.has = true;
    snapshot.arg2 = header.arg2;
    snapshot.arg3 = header.arg3;
    snapshot.block_cursor = header.block_cursor;
    snapshot.block_count = header.block_count;
    snapshot.place_node_offset = header.place_node_offset;
    snapshot.entity_node_offset = header.entity_node_offset;
    snapshot.target_id = header.target_id;
    snapshot.source_x = header.source_x;
    snapshot.source_y = header.source_y;
    snapshot.source_z = header.source_z;
    snapshot.captured_place_desc = header.captured_place_desc;
    snapshot.captured_entity_desc = header.captured_entity_desc;
    snapshot.captured_entity_mutation_desc = header.captured_entity_mutation_desc;

    const bool body_ok =
        std::fread(snapshot.queue, 1, kSharedQueueCopySize, file) == kSharedQueueCopySize &&
        std::fread(snapshot.block, 1, kSharedBlockCopySize, file) == kSharedBlockCopySize;
    std::fclose(file);
    if (!body_ok) {
        log_line("shared_template_load_failed short_read path=%S", kSharedTemplatePath);
        return false;
    }

    patch_shared_block_runtime_descriptors(snapshot.block, snapshot);
    *snapshot_out = snapshot;
    log_line(
        "shared_template_loaded path=%S cursor=%u count=%u place_node=0x%X entity_node=0x%X target_id=%d source=%d,%d,%d",
        kSharedTemplatePath,
        static_cast<unsigned>(snapshot.block_cursor),
        static_cast<unsigned>(snapshot.block_count),
        static_cast<unsigned>(snapshot.place_node_offset),
        static_cast<unsigned>(snapshot.entity_node_offset),
        snapshot.target_id,
        snapshot.source_x,
        snapshot.source_y,
        snapshot.source_z);
    return true;
}

void capture_latest_shared(
    void* owner,
    void* queue,
    void* block,
    uint64_t arg2,
    uint64_t arg3,
    uint16_t block_cursor,
    uint16_t block_count,
    uint16_t place_node_offset,
    const unsigned char* queue_copy,
    const unsigned char* block_copy) {
    SharedSnapshot snapshot{};
    snapshot.has = true;
    snapshot.owner = owner;
    snapshot.queue_original = queue;
    snapshot.block_original = block;
    snapshot.arg2 = arg2;
    snapshot.arg3 = arg3;
    snapshot.block_cursor = block_cursor;
    snapshot.block_count = block_count;
    snapshot.place_node_offset = place_node_offset;
    snapshot.target_registry = g_latest_target_registry;
    snapshot.target_id = g_latest_target_id;
    snapshot.source_x = read_i32(block_copy, place_node_offset + 0x20);
    snapshot.source_y = read_i32(block_copy, place_node_offset + 0x24);
    snapshot.source_z = read_i32(block_copy, place_node_offset + 0x28);
    snapshot.captured_place_desc = read_u64(block_copy, place_node_offset + 0x00);
    snapshot.captured_entity_desc = runtime_entity_placement_descriptor();
    snapshot.captured_entity_mutation_desc = runtime_entity_mutation_descriptor();
    uint16_t entity_entry_offset = 0;
    find_entity_placement_node_offset(
        block_copy,
        kSharedBlockCopySize,
        &snapshot.entity_node_offset,
        &entity_entry_offset);
    std::memcpy(snapshot.queue, queue_copy, kSharedQueueCopySize);
    std::memcpy(snapshot.block, block_copy, kSharedBlockCopySize);

    {
        std::lock_guard<std::mutex> lock(g_snapshot_mutex);
        g_latest_shared = snapshot;
    }

    void* prefab_entry = reinterpret_cast<void*>(read_u64(block_copy, place_node_offset + 0x18));
    remember_file_prefab_entry("shared_capture", std::string(), prefab_entry, nullptr);
    persist_shared_template(snapshot);
}

uint8_t reset_shared_owner_busy_state(void* owner) {
    if (!owner) {
        return 0xff;
    }

    __try {
        auto* busy = reinterpret_cast<uint8_t*>(owner) + 0x120;
        const uint8_t previous = *busy;
        *busy = 0;
        return previous;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return 0xff;
    }
}

int capture_shared_exception(EXCEPTION_POINTERS* exception) {
    if (exception && exception->ExceptionRecord) {
        g_last_shared_exception_code = exception->ExceptionRecord->ExceptionCode;
        g_last_shared_exception_address = exception->ExceptionRecord->ExceptionAddress;
        if (exception->ContextRecord) {
            g_last_shared_exception_rcx = reinterpret_cast<void*>(exception->ContextRecord->Rcx);
            g_last_shared_exception_rdx = reinterpret_cast<void*>(exception->ContextRecord->Rdx);
            g_last_shared_exception_r8 = reinterpret_cast<void*>(exception->ContextRecord->R8);
            g_last_shared_exception_r9 = reinterpret_cast<void*>(exception->ContextRecord->R9);
            g_last_shared_exception_rsp = reinterpret_cast<void*>(exception->ContextRecord->Rsp);
        }
    } else {
        g_last_shared_exception_code = 0;
        g_last_shared_exception_address = nullptr;
        g_last_shared_exception_rcx = nullptr;
        g_last_shared_exception_rdx = nullptr;
        g_last_shared_exception_r8 = nullptr;
        g_last_shared_exception_r9 = nullptr;
        g_last_shared_exception_rsp = nullptr;
    }
    return EXCEPTION_EXECUTE_HANDLER;
}

bool call_original_shared_guarded(void* owner, void* queue, uint64_t arg2, uint64_t arg3, uint64_t* result_out) {
    g_last_shared_exception_code = 0;
    g_last_shared_exception_address = nullptr;
    g_last_shared_exception_rcx = nullptr;
    g_last_shared_exception_rdx = nullptr;
    g_last_shared_exception_r8 = nullptr;
    g_last_shared_exception_r9 = nullptr;
    g_last_shared_exception_rsp = nullptr;
    __try {
        g_shared_replay_in_progress = true;
        g_replay_in_progress = true;
        const uint64_t result = g_original_shared(owner, queue, arg2, arg3);
        g_replay_in_progress = false;
        g_shared_replay_in_progress = false;
        if (result_out) {
            *result_out = result;
        }
        return true;
    } __except (capture_shared_exception(GetExceptionInformation())) {
        g_replay_in_progress = false;
        g_shared_replay_in_progress = false;
        return false;
    }
}

bool allocate_fresh_target_id(void* registry, int32_t* target_id_out) {
    if (!registry || !target_id_out) {
        return false;
    }

    int32_t target_id = -1;
    int32_t next_id = -1;
    if (!emulate_target_allocator(registry, &target_id, &target_id, &next_id)) {
        log_line(
            "target_allocator_alloc_skip registry=%p writable=%d",
            registry,
            is_writable_memory(static_cast<unsigned char*>(registry) + 0x40, sizeof(int32_t)) ? 1 : 0);
        return false;
    }

    if (target_id < 0) {
        return false;
    }

    *target_id_out = target_id;
    return true;
}

bool safe_read_i32_mem(const void* base, size_t offset, int32_t* value_out) {
    if (!base || !value_out) {
        return false;
    }

    __try {
        *value_out = *reinterpret_cast<const int32_t*>(static_cast<const unsigned char*>(base) + offset);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

bool safe_read_u32_mem(const void* base, size_t offset, uint32_t* value_out) {
    if (!base || !value_out) {
        return false;
    }

    __try {
        *value_out = *reinterpret_cast<const uint32_t*>(static_cast<const unsigned char*>(base) + offset);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

bool safe_read_u64_mem(const void* base, size_t offset, uint64_t* value_out) {
    if (!base || !value_out) {
        return false;
    }

    __try {
        *value_out = *reinterpret_cast<const uint64_t*>(static_cast<const unsigned char*>(base) + offset);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

bool looks_like_user_pointer(uint64_t value) {
    return value > 0x10000ull && value < 0x0000800000000000ull;
}

bool derive_shared_owner_from_place_context(
    void* place_context,
    void** owner_out,
    void** owner_surface_out,
    const char** source_out) {
    if (owner_out) {
        *owner_out = nullptr;
    }
    if (owner_surface_out) {
        *owner_surface_out = nullptr;
    }
    if (source_out) {
        *source_out = "";
    }
    if (!place_context) {
        return false;
    }

    uint64_t owner_surface = 0;
    uint64_t owner = 0;
    if (safe_read_u64_mem(place_context, 0x160, &owner_surface) &&
        looks_like_user_pointer(owner_surface) &&
        safe_read_u64_mem(reinterpret_cast<void*>(owner_surface), 0x988, &owner) &&
        looks_like_user_pointer(owner)) {
        if (owner_out) {
            *owner_out = reinterpret_cast<void*>(owner);
        }
        if (owner_surface_out) {
            *owner_surface_out = reinterpret_cast<void*>(owner_surface);
        }
        if (source_out) {
            *source_out = "place_context_160_988";
        }
        return true;
    }

    if (safe_read_u64_mem(place_context, 0x988, &owner) && looks_like_user_pointer(owner)) {
        if (owner_out) {
            *owner_out = reinterpret_cast<void*>(owner);
        }
        if (owner_surface_out) {
            *owner_surface_out = place_context;
        }
        if (source_out) {
            *source_out = "place_context_988";
        }
        return true;
    }

    return false;
}

bool read_binary_file(const std::string& path, std::vector<unsigned char>* bytes_out) {
    if (!bytes_out || path.empty()) {
        return false;
    }

    FILE* file = nullptr;
    fopen_s(&file, path.c_str(), "rb");
    if (!file) {
        return false;
    }

    if (std::fseek(file, 0, SEEK_END) != 0) {
        std::fclose(file);
        return false;
    }
    const long size = std::ftell(file);
    if (size <= 0) {
        std::fclose(file);
        return false;
    }
    std::rewind(file);

    std::vector<unsigned char> bytes(static_cast<size_t>(size));
    const size_t read = std::fread(bytes.data(), 1, bytes.size(), file);
    std::fclose(file);
    if (read != bytes.size()) {
        return false;
    }

    *bytes_out = std::move(bytes);
    return true;
}

int hex_digit_value(char value) {
    if (value >= '0' && value <= '9') {
        return value - '0';
    }
    if (value >= 'a' && value <= 'f') {
        return 10 + value - 'a';
    }
    if (value >= 'A' && value <= 'F') {
        return 10 + value - 'A';
    }
    return -1;
}

bool parse_prefab_hash_qwords(const std::string& hash_hex, uint64_t* qwords_out) {
    if (!qwords_out || hash_hex.size() != 64) {
        return false;
    }

    uint64_t qwords[4]{};
    for (size_t part = 0; part < 4; ++part) {
        uint64_t value = 0;
        for (size_t byte_index = 0; byte_index < 8; ++byte_index) {
            const size_t offset = part * 16 + byte_index * 2;
            const int high = hex_digit_value(hash_hex[offset]);
            const int low = hex_digit_value(hash_hex[offset + 1]);
            if (high < 0 || low < 0) {
                return false;
            }
            const uint64_t byte_value = static_cast<uint64_t>((high << 4) | low);
            value |= byte_value << (byte_index * 8);
        }
        qwords[part] = value;
    }

    for (size_t index = 0; index < 4; ++index) {
        qwords_out[index] = qwords[index];
    }
    return true;
}

bool read_prefab_entry_hash_qwords(void* entry, uint64_t* qwords_out) {
    if (!entry || !qwords_out) {
        return false;
    }

    return safe_read_u64_mem(entry, 0x28, &qwords_out[0]) &&
        safe_read_u64_mem(entry, 0x30, &qwords_out[1]) &&
        safe_read_u64_mem(entry, 0x38, &qwords_out[2]) &&
        safe_read_u64_mem(entry, 0x40, &qwords_out[3]);
}

bool prefab_hash_qwords_equal(const uint64_t* left, const uint64_t* right) {
    return left && right &&
        left[0] == right[0] &&
        left[1] == right[1] &&
        left[2] == right[2] &&
        left[3] == right[3];
}

bool prefab_entry_matches_hash(void* entry, const uint64_t* hash_qwords) {
    uint64_t entry_hash[4]{};
    return read_prefab_entry_hash_qwords(entry, entry_hash) &&
        prefab_hash_qwords_equal(entry_hash, hash_qwords);
}

bool prefab_hash_qwords_any(const uint64_t* qwords) {
    return qwords && (qwords[0] != 0 || qwords[1] != 0 || qwords[2] != 0 || qwords[3] != 0);
}

bool prefab_entry_ready_for_hash(void* entry, const uint64_t* hash_qwords) {
    if (!entry) {
        return false;
    }

    uint64_t entry_hash[4]{};
    if (!read_prefab_entry_hash_qwords(entry, entry_hash) || !prefab_hash_qwords_any(entry_hash)) {
        return false;
    }
    if (hash_qwords && !prefab_hash_qwords_equal(entry_hash, hash_qwords)) {
        return false;
    }

    uint64_t archive = 0;
    uint64_t payload = 0;
    int32_t brick_count = 0;
    int32_t byte_count = 0;
    safe_read_u64_mem(entry, 0xF0, &archive);
    safe_read_u64_mem(entry, 0xF8, &payload);
    safe_read_i32_mem(entry, 0xBC, &brick_count);
    safe_read_i32_mem(entry, 0xC0, &byte_count);

    return archive != 0 && payload != 0 && brick_count > 0 && byte_count > 0;
}

bool wait_prefab_entry_ready(
    void* entry,
    const uint64_t* hash_qwords,
    DWORD timeout_ms,
    DWORD* waited_ms_out) {
    const DWORD start = GetTickCount();
    while (true) {
        if (prefab_entry_ready_for_hash(entry, hash_qwords)) {
            if (waited_ms_out) {
                *waited_ms_out = GetTickCount() - start;
            }
            return true;
        }

        const DWORD elapsed = GetTickCount() - start;
        if (elapsed >= timeout_ms) {
            if (waited_ms_out) {
                *waited_ms_out = elapsed;
            }
            return false;
        }
        Sleep(50);
    }
}

void* cache_entry_at(void* cache_owner, int32_t index) {
    if (!cache_owner || index < 0) {
        return nullptr;
    }

    uint64_t entries = 0;
    if (!safe_read_u64_mem(cache_owner, 0x38, &entries) || entries == 0) {
        return nullptr;
    }

    uint64_t entry = 0;
    if (!safe_read_u64_mem(reinterpret_cast<void*>(entries), static_cast<size_t>(index) * sizeof(uint64_t), &entry)) {
        return nullptr;
    }

    return reinterpret_cast<void*>(entry);
}

void remember_file_prefab_entry(
    const char* reason,
    const std::string& path,
    void* entry,
    const uint64_t* hash_qwords) {
    if (!entry) {
        return;
    }

    uint64_t entry_hash[4]{};
    const uint64_t* stored_hash = hash_qwords;
    if (!stored_hash && read_prefab_entry_hash_qwords(entry, entry_hash)) {
        stored_hash = entry_hash;
    }

    {
        std::lock_guard<std::mutex> lock(g_snapshot_mutex);
        g_file_prefab_entry = entry;
        if (!path.empty()) {
            g_file_prefab_path = path;
        }
        if (stored_hash) {
            for (size_t index = 0; index < 4; ++index) {
                g_file_prefab_hash_qwords[index] = stored_hash[index];
            }
            g_file_prefab_hash_valid = true;
        }
    }

    log_line(
        "file_prefab_remembered reason=%s path=%s entry=%p hash_valid=%d",
        reason ? reason : "",
        path.c_str(),
        entry,
        stored_hash ? 1 : 0);
}

void mark_file_prefab_pending(const std::string& path, const uint64_t* hash_qwords) {
    std::lock_guard<std::mutex> lock(g_snapshot_mutex);
    g_file_prefab_pending_path = path;
    g_file_prefab_pending_hash_valid = hash_qwords != nullptr;
    if (hash_qwords) {
        for (size_t index = 0; index < 4; ++index) {
            g_file_prefab_pending_hash_qwords[index] = hash_qwords[index];
        }
    }
    g_file_prefab_pending_started_ms = GetTickCount();
}

void clear_file_prefab_pending() {
    std::lock_guard<std::mutex> lock(g_snapshot_mutex);
    g_file_prefab_pending_path.clear();
    g_file_prefab_pending_hash_valid = false;
    g_file_prefab_pending_started_ms = 0;
}

bool file_prefab_pending_matches(const std::string& path, const uint64_t* hash_qwords, DWORD* age_ms_out) {
    std::lock_guard<std::mutex> lock(g_snapshot_mutex);
    const bool path_match = !path.empty() && g_file_prefab_pending_path == path;
    const bool hash_match =
        hash_qwords &&
        g_file_prefab_pending_hash_valid &&
        prefab_hash_qwords_equal(g_file_prefab_pending_hash_qwords, hash_qwords);
    if (!path_match && !hash_match) {
        return false;
    }
    if (age_ms_out) {
        *age_ms_out = GetTickCount() - g_file_prefab_pending_started_ms;
    }
    return true;
}

void* find_cached_prefab_entry_by_hash_table(void* cache_owner, const uint64_t* hash_qwords, int32_t* count_out) {
    if (count_out) {
        *count_out = -1;
    }
    if (!cache_owner || !hash_qwords) {
        return nullptr;
    }

    int32_t active_count = 0;
    int32_t sentinel_count = 0;
    if (!safe_read_i32_mem(cache_owner, 0x50, &active_count) ||
        !safe_read_i32_mem(cache_owner, 0x7C, &sentinel_count)) {
        return nullptr;
    }
    if (count_out) {
        *count_out = active_count;
    }
    if (active_count == sentinel_count || active_count <= 0 || active_count > 65536) {
        return nullptr;
    }

    int32_t bucket_count = 0;
    if (!safe_read_i32_mem(cache_owner, 0x90, &bucket_count) ||
        bucket_count <= 0 ||
        bucket_count > 1048576) {
        return nullptr;
    }

    uint64_t buckets = 0;
    if (!safe_read_u64_mem(cache_owner, 0x88, &buckets) || buckets == 0) {
        buckets = reinterpret_cast<uint64_t>(cache_owner) + 0x80;
    }

    const uint32_t* hash_words = reinterpret_cast<const uint32_t*>(hash_qwords);
    const uint32_t bucket_mask = static_cast<uint32_t>(bucket_count - 1);
    uint32_t chain_index = 0xFFFFFFFFu;
    if (!safe_read_u32_mem(
            reinterpret_cast<void*>(buckets),
            static_cast<size_t>(bucket_mask & hash_words[0]) * sizeof(uint32_t),
            &chain_index) ||
        chain_index == 0xFFFFFFFFu) {
        return nullptr;
    }

    uint64_t records = 0;
    if (!safe_read_u64_mem(cache_owner, 0x48, &records) || records == 0) {
        return nullptr;
    }

    int32_t bit_limit = 0;
    safe_read_i32_mem(cache_owner, 0x70, &bit_limit);
    uint64_t bitset = 0;
    if (!safe_read_u64_mem(cache_owner, 0x68, &bitset) || bitset == 0) {
        bitset = reinterpret_cast<uint64_t>(cache_owner) + 0x58;
    }

    for (int guard = 0; guard < 8192 && chain_index != 0xFFFFFFFFu; ++guard) {
        if (static_cast<int32_t>(chain_index) < 0 ||
            static_cast<int32_t>(chain_index) >= active_count ||
            static_cast<int32_t>(chain_index) >= bit_limit) {
            return nullptr;
        }

        uint32_t bit_word = 0;
        if (!safe_read_u32_mem(
                reinterpret_cast<void*>(bitset),
                static_cast<size_t>(chain_index >> 5) * sizeof(uint32_t),
                &bit_word) ||
            ((bit_word >> (chain_index & 0x1F)) & 1u) == 0) {
            return nullptr;
        }

        void* record = reinterpret_cast<void*>(records + static_cast<uint64_t>(chain_index) * 0x30ull);
        bool match = true;
        for (size_t index = 0; index < 8; ++index) {
            uint32_t stored = 0;
            if (!safe_read_u32_mem(record, index * sizeof(uint32_t), &stored) ||
                stored != hash_words[index]) {
                match = false;
                break;
            }
        }
        if (match) {
            uint64_t entry = 0;
            if (safe_read_u64_mem(record, 0x20, &entry)) {
                return reinterpret_cast<void*>(entry);
            }
            return nullptr;
        }

        if (!safe_read_u32_mem(record, 0x28, &chain_index)) {
            return nullptr;
        }
    }

    return nullptr;
}

void* find_cached_prefab_entry_by_hash(void* cache_owner, const uint64_t* hash_qwords, int32_t* count_out) {
    if (count_out) {
        *count_out = -1;
    }
    if (!cache_owner || !hash_qwords) {
        return nullptr;
    }

    void* hash_table_entry = find_cached_prefab_entry_by_hash_table(cache_owner, hash_qwords, count_out);
    if (hash_table_entry) {
        return hash_table_entry;
    }

    int32_t count = -1;
    if (!safe_read_i32_mem(cache_owner, 0x40, &count)) {
        return nullptr;
    }
    if (count_out) {
        *count_out = count;
    }
    if (count <= 0 || count > 8192) {
        return nullptr;
    }

    for (int32_t index = 0; index < count; ++index) {
        void* entry = cache_entry_at(cache_owner, index);
        if (prefab_entry_matches_hash(entry, hash_qwords)) {
            return entry;
        }
    }
    return nullptr;
}

bool call_raw_prefab_cache_guarded(
    void* cache_owner,
    const std::vector<unsigned char>& bytes,
    bool* exception_out) {
    if (exception_out) {
        *exception_out = false;
    }
    if (!cache_owner || bytes.empty()) {
        return false;
    }

    RawPrefabCacheFn raw_cache = runtime_raw_prefab_cache();
    if (!raw_cache) {
        return false;
    }

    uint64_t raw_buffer_and_len[2] = {
        reinterpret_cast<uint64_t>(bytes.data()),
        static_cast<uint64_t>(bytes.size()),
    };
    uint64_t callback_state[2] = {0, 0};

    __try {
        raw_cache(cache_owner, raw_buffer_and_len, callback_state);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        if (exception_out) {
            *exception_out = true;
        }
        return false;
    }
}

bool materialize_prefab_file(
    const std::string& path,
    void* cache_owner,
    const std::string& hash_hex,
    void** prefab_entry_out,
    int32_t* before_count_out,
    int32_t* after_count_out,
    bool* raw_exception_out,
    bool* pending_out) {
    if (prefab_entry_out) {
        *prefab_entry_out = nullptr;
    }
    if (before_count_out) {
        *before_count_out = -1;
    }
    if (after_count_out) {
        *after_count_out = -1;
    }
    if (raw_exception_out) {
        *raw_exception_out = false;
    }
    if (pending_out) {
        *pending_out = false;
    }
    if (path.empty() || !cache_owner || !prefab_entry_out) {
        return false;
    }

    uint64_t requested_hash[4]{};
    const bool has_requested_hash = parse_prefab_hash_qwords(hash_hex, requested_hash);

    {
        std::lock_guard<std::mutex> lock(g_snapshot_mutex);
        const bool cached_path_match = g_file_prefab_path == path;
        const bool cached_hash_match =
            has_requested_hash &&
            g_file_prefab_hash_valid &&
            prefab_hash_qwords_equal(g_file_prefab_hash_qwords, requested_hash);
        if (g_file_prefab_entry && (cached_path_match || cached_hash_match)) {
            if (!prefab_entry_ready_for_hash(
                    g_file_prefab_entry,
                    has_requested_hash ? requested_hash : nullptr)) {
                log_line(
                    "file_prefab_reused_unready path=%s entry=%p path_match=%d hash_match=%d",
                    path.c_str(),
                    g_file_prefab_entry,
                    cached_path_match ? 1 : 0,
                    cached_hash_match ? 1 : 0);
                log_prefab_entry_fields("file_reused_unready", path.c_str(), g_file_prefab_entry);
            } else {
                *prefab_entry_out = g_file_prefab_entry;
                int32_t count = -1;
                safe_read_i32_mem(cache_owner, 0x50, &count);
                if (before_count_out) {
                    *before_count_out = count;
                }
                if (after_count_out) {
                    *after_count_out = count;
                }
                log_line(
                    "file_prefab_reused remembered=1 path=%s entry=%p path_match=%d hash_match=%d count=%d",
                    path.c_str(),
                    g_file_prefab_entry,
                    cached_path_match ? 1 : 0,
                    cached_hash_match ? 1 : 0,
                    count);
                log_prefab_entry_fields("file_reused_ready", path.c_str(), g_file_prefab_entry);
                return true;
            }
        }
    }

    int32_t existing_count = -1;
    if (has_requested_hash) {
        void* existing_entry = find_cached_prefab_entry_by_hash(cache_owner, requested_hash, &existing_count);
        if (existing_entry) {
            if (!prefab_entry_ready_for_hash(existing_entry, requested_hash)) {
                if (pending_out) {
                    *pending_out = true;
                }
                log_line(
                    "file_prefab_cache_hash_hit_unready path=%s entry=%p count=%d",
                    path.c_str(),
                    existing_entry,
                    existing_count);
                log_prefab_entry_fields("file_cache_hash_hit_unready", path.c_str(), existing_entry);
                return false;
            }
            *prefab_entry_out = existing_entry;
            if (before_count_out) {
                *before_count_out = existing_count;
            }
            if (after_count_out) {
                *after_count_out = existing_count;
            }
            remember_file_prefab_entry("cache_hash_hit", path, existing_entry, requested_hash);
            log_prefab_entry_fields("file_cache_hash_hit", path.c_str(), existing_entry);
            clear_file_prefab_pending();
            return true;
        }

        DWORD pending_age_ms = 0;
        if (file_prefab_pending_matches(path, requested_hash, &pending_age_ms) &&
            pending_age_ms < 30000) {
            if (before_count_out) {
                *before_count_out = existing_count;
            }
            if (after_count_out) {
                *after_count_out = existing_count;
            }
            if (pending_out) {
                *pending_out = true;
            }
            log_line(
                "file_prefab_seed_pending path=%s cache=%p count=%d age_ms=%lu",
                path.c_str(),
                cache_owner,
                existing_count,
                pending_age_ms);
            return false;
        }

        log_line(
            "file_prefab_cache_hash_miss path=%s cache=%p count=%d",
            path.c_str(),
            cache_owner,
            existing_count);
    }

    std::vector<unsigned char> bytes;
    if (!read_binary_file(path, &bytes)) {
        return false;
    }

    int32_t before_count = -1;
    safe_read_i32_mem(cache_owner, 0x50, &before_count);
    bool raw_exception = false;
    const bool raw_ok = call_raw_prefab_cache_guarded(cache_owner, bytes, &raw_exception);
    int32_t after_count = -1;
    safe_read_i32_mem(cache_owner, 0x50, &after_count);
    if (before_count_out) {
        *before_count_out = before_count;
    }
    if (after_count_out) {
        *after_count_out = after_count;
    }
    if (raw_exception_out) {
        *raw_exception_out = raw_exception;
    }

    if (!raw_ok || raw_exception) {
        clear_file_prefab_pending();
        log_line(
            "file_prefab_materialize_failed path=%s cache=%p raw_ok=%d raw_exception=%d count_before=%d count_after=%d",
            path.c_str(),
            cache_owner,
            raw_ok ? 1 : 0,
            raw_exception ? 1 : 0,
            before_count,
            after_count);
        return false;
    }

    if (has_requested_hash) {
        void* immediate_entry = find_cached_prefab_entry_by_hash(cache_owner, requested_hash, &existing_count);
        if (immediate_entry && prefab_entry_ready_for_hash(immediate_entry, requested_hash)) {
            remember_file_prefab_entry("raw_materialized_ready_immediate", path, immediate_entry, requested_hash);
            *prefab_entry_out = immediate_entry;
            if (after_count_out) {
                *after_count_out = existing_count;
            }
            clear_file_prefab_pending();
            log_line(
                "file_prefab_materialized path=%s cache=%p entry=%p bytes=%zu raw_ok=%d raw_exception=%d count_before=%d count_after=%d",
                path.c_str(),
                cache_owner,
                immediate_entry,
                bytes.size(),
                raw_ok ? 1 : 0,
                raw_exception ? 1 : 0,
                before_count,
                existing_count);
            log_prefab_entry_fields("file_materialized", path.c_str(), immediate_entry);
            return true;
        }

        mark_file_prefab_pending(path, requested_hash);
        if (pending_out) {
            *pending_out = true;
        }
        log_line(
            "file_prefab_materialize_pending path=%s cache=%p bytes=%zu raw_ok=%d raw_exception=%d count_before=%d count_after=%d",
            path.c_str(),
            cache_owner,
            bytes.size(),
            raw_ok ? 1 : 0,
            raw_exception ? 1 : 0,
            before_count,
            after_count);
        return false;
    }

    log_line(
        "file_prefab_materialize_pending_no_hash path=%s cache=%p bytes=%zu raw_ok=%d raw_exception=%d count_before=%d count_after=%d",
        path.c_str(),
        cache_owner,
        bytes.size(),
        raw_ok ? 1 : 0,
        raw_exception ? 1 : 0,
        before_count,
        after_count);
    if (pending_out) {
        *pending_out = true;
    }
    return false;
}

bool seed_prefab_file(
    const char* nonce,
    void* cache_owner,
    const std::string& prefab_path,
    const std::string& prefab_hash_hex) {
    if (!cache_owner || prefab_path.empty()) {
        write_status(
            "ok=0 nonce=%s error=file_seed_missing_command_fields cache=%p path_present=%d",
            nonce ? nonce : "",
            cache_owner,
            prefab_path.empty() ? 0 : 1);
        log_line(
            "file_seed_failed nonce=%s missing_fields cache=%p path=%s",
            nonce ? nonce : "",
            cache_owner,
            prefab_path.c_str());
        return true;
    }

    void* prefab_entry = nullptr;
    int32_t cache_count_before = -1;
    int32_t cache_count_after = -1;
    bool raw_exception = false;
    bool pending = false;
    if (!materialize_prefab_file(
            prefab_path,
            cache_owner,
            prefab_hash_hex,
            &prefab_entry,
            &cache_count_before,
            &cache_count_after,
            &raw_exception,
            &pending) ||
        !prefab_entry) {
        if (pending) {
            write_status(
                "ok=0 nonce=%s pending=1 error=file_seed_pending cache=%p path=%s raw_exception=%d count_before=%d count_after=%d",
                nonce ? nonce : "",
                cache_owner,
                prefab_path.c_str(),
                raw_exception ? 1 : 0,
                cache_count_before,
                cache_count_after);
            log_line(
                "file_seed_pending nonce=%s cache=%p path=%s raw_exception=%d count_before=%d count_after=%d",
                nonce ? nonce : "",
                cache_owner,
                prefab_path.c_str(),
                raw_exception ? 1 : 0,
                cache_count_before,
                cache_count_after);
            return true;
        }

        write_status(
            "ok=0 nonce=%s error=file_seed_materialize_failed cache=%p path=%s raw_exception=%d count_before=%d count_after=%d",
            nonce ? nonce : "",
            cache_owner,
            prefab_path.c_str(),
            raw_exception ? 1 : 0,
            cache_count_before,
            cache_count_after);
        log_line(
            "file_seed_failed nonce=%s materialize_failed cache=%p path=%s raw_exception=%d count_before=%d count_after=%d",
            nonce ? nonce : "",
            cache_owner,
            prefab_path.c_str(),
            raw_exception ? 1 : 0,
            cache_count_before,
            cache_count_after);
        return true;
    }

    write_status(
        "ok=1 nonce=%s method=file_seed prefab=%p cache_count_before=%d cache_count_after=%d raw_exception=%d",
        nonce ? nonce : "",
        prefab_entry,
        cache_count_before,
        cache_count_after,
        raw_exception ? 1 : 0);
    log_line(
        "file_seed_accepted nonce=%s prefab=%p cache=%p path=%s count_before=%d count_after=%d",
        nonce ? nonce : "",
        prefab_entry,
        cache_owner,
        prefab_path.c_str(),
        cache_count_before,
        cache_count_after);
    return true;
}

bool select_shared_template_for_file_spawn(
    void* owner,
    void* preferred_target_registry,
    bool allow_disk_owner,
    SharedSnapshot* snapshot_out,
    bool* loaded_from_disk_out) {
    if (loaded_from_disk_out) {
        *loaded_from_disk_out = false;
    }
    if (!snapshot_out) {
        return false;
    }

    SharedSnapshot snapshot{};
    void* latest_target_registry = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_snapshot_mutex);
        snapshot = g_latest_shared;
        latest_target_registry = g_latest_target_registry;
    }

    bool loaded_from_disk = false;
    if (!snapshot.has) {
        if (!load_shared_template_from_disk(&snapshot)) {
            return false;
        }
        loaded_from_disk = true;
    }

    if (loaded_from_disk && !snapshot.owner && (!allow_disk_owner || !owner)) {
        log_line(
            "file_shared_disk_template_missing_live_owner command_owner=%p registry=%p",
            owner,
            preferred_target_registry ? preferred_target_registry : latest_target_registry);
        return false;
    }

    if (!snapshot.owner) {
        snapshot.owner = owner;
    } else if (owner && owner != snapshot.owner) {
        log_line(
            "file_shared_preserving_captured_owner captured_owner=%p command_owner=%p loaded_from_disk=%d",
            snapshot.owner,
            owner,
            loaded_from_disk ? 1 : 0);
    }
    snapshot.target_registry =
        preferred_target_registry ? preferred_target_registry :
        snapshot.target_registry ? snapshot.target_registry :
        latest_target_registry;
    if (snapshot.target_id < 0 &&
        snapshot.place_node_offset != 0 &&
        static_cast<size_t>(snapshot.place_node_offset) + 0x14 <= kSharedBlockCopySize) {
        snapshot.target_id = static_cast<int32_t>(read_u32(snapshot.block, snapshot.place_node_offset + 0x10));
    }

    if (!snapshot.owner || !snapshot.target_registry || snapshot.place_node_offset == 0) {
        return false;
    }

    *snapshot_out = snapshot;
    if (loaded_from_disk_out) {
        *loaded_from_disk_out = loaded_from_disk;
    }
    return true;
}

bool spawn_shared_snapshot(
    const char* nonce,
    SharedSnapshot snapshot,
    const char* method_label,
    int32_t x_offset,
    int32_t y_offset,
    int32_t z_offset,
    bool has_absolute,
    int32_t absolute_x,
    int32_t absolute_y,
    int32_t absolute_z,
    void* prefab_entry_override,
    int32_t orientation_override,
    int32_t cache_count_before,
    int32_t cache_count_after) {
    const char* method = method_label ? method_label : "shared";
    if (!g_original_shared) {
        write_status("ok=0 nonce=%s error=%s_missing_shared_submit", nonce ? nonce : "", method);
        return true;
    }
    if (!snapshot.owner || !snapshot.target_registry || snapshot.place_node_offset == 0) {
        write_status(
            "ok=0 nonce=%s error=%s_missing_template_context owner=%p registry=%p place_node=0x%X",
            nonce ? nonce : "",
            method,
            snapshot.owner,
            snapshot.target_registry,
            static_cast<unsigned>(snapshot.place_node_offset));
        log_line(
            "spawn_failed_%s nonce=%s missing_template_context owner=%p registry=%p place_node=0x%X",
            method,
            nonce ? nonce : "",
            snapshot.owner,
            snapshot.target_registry,
            static_cast<unsigned>(snapshot.place_node_offset));
        return true;
    }

    const uint32_t old_target_id = read_u32(snapshot.block, snapshot.place_node_offset + 0x10);
    int32_t fresh_target_id = -1;
    if (!allocate_fresh_target_id(snapshot.target_registry, &fresh_target_id)) {
        write_status(
            "ok=0 nonce=%s error=%s_target_allocator_unavailable registry=%p prefab=%p cache_count_before=%d cache_count_after=%d",
            nonce ? nonce : "",
            method,
            snapshot.target_registry,
            prefab_entry_override,
            cache_count_before,
            cache_count_after);
        log_line(
            "spawn_failed_%s nonce=%s target_allocator_unavailable registry=%p old_target_id=%u snapshot_target_id=%d installed=%d",
            method,
            nonce ? nonce : "",
            snapshot.target_registry,
            static_cast<unsigned>(old_target_id),
            snapshot.target_id,
            g_target_allocator_installed.load() ? 1 : 0);
        return true;
    }

    auto* queue = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, kSharedQueueCopySize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    auto* block = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, kSharedBlockCopySize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    if (!queue || !block) {
        write_status("ok=0 nonce=%s error=%s_replay_alloc_failed", nonce ? nonce : "", method);
        log_line(
            "spawn_failed_%s nonce=%s alloc queue=%p block=%p gle=%lu",
            method,
            nonce ? nonce : "",
            queue,
            block,
            GetLastError());
        return true;
    }

    std::memcpy(queue, snapshot.queue, kSharedQueueCopySize);
    std::memcpy(block, snapshot.block, kSharedBlockCopySize);
    patch_shared_block_runtime_descriptors(block, snapshot);

    prepare_shared_queue_for_replay(queue, block, snapshot.block_count);
    write_u64(block, 0x00, 0);
    write_u64(block, 0x08, 0);

    const int32_t source_x = snapshot.source_x;
    const int32_t source_y = snapshot.source_y;
    const int32_t source_z = snapshot.source_z;
    const int32_t spawn_x = has_absolute ? absolute_x : source_x + x_offset;
    const int32_t spawn_y = has_absolute ? absolute_y : source_y + y_offset;
    const int32_t spawn_z = has_absolute ? absolute_z : source_z + z_offset;
    const int32_t delta_x = spawn_x - source_x;
    const int32_t delta_y = spawn_y - source_y;
    const int32_t delta_z = spawn_z - source_z;

    const uintptr_t place_desc = runtime_place_prefab_descriptor();
    const uintptr_t entity_mutation_desc = runtime_entity_mutation_descriptor();
    const uintptr_t entity_desc = runtime_entity_placement_descriptor();
    const uint16_t count = read_u16(block, 0x14);
    const uint16_t limit = count > kSharedNodeScanLimit ? kSharedNodeScanLimit : count;
    uint16_t patched = 0;
    uint16_t target_patched = 0;
    uint16_t target_generic_patched = 0;
    uint16_t entity_position_patched = 0;
    uint16_t entity_transform_patched = 0;
    uint16_t place_local_preserved = 0;
    uint16_t entity_fallback_preserved = 0;
    uint16_t target_mismatch = 0;
    uint16_t prefab_patched = 0;
    uint16_t orientation_patched = 0;
    bool entity_target_present = false;
    for (uint16_t i = 0; i < limit; ++i) {
        uint16_t entry_offset = 0;
        uint16_t node_offset = 0;
        if (!shared_node_offset_by_index(block, kSharedBlockCopySize, i, &entry_offset, &node_offset)) {
            continue;
        }
        if (static_cast<size_t>(node_offset) + 0x30 > kSharedBlockCopySize) {
            continue;
        }

        if (read_u64(block, node_offset) == entity_desc &&
            read_u32(block, node_offset + 0x10) == old_target_id) {
            entity_target_present = true;
            break;
        }
    }

    for (uint16_t i = 0; i < limit; ++i) {
        uint16_t entry_offset = 0;
        uint16_t node_offset = 0;
        if (!shared_node_offset_by_index(block, kSharedBlockCopySize, i, &entry_offset, &node_offset)) {
            continue;
        }
        if (static_cast<size_t>(node_offset) + 0x30 > kSharedBlockCopySize) {
            continue;
        }

        const uint64_t descriptor = read_u64(block, node_offset);
        const uint32_t node_target_id = read_u32(block, node_offset + 0x10);
        const bool is_known_target_node =
            descriptor == place_desc ||
            descriptor == entity_desc ||
            descriptor == entity_mutation_desc;
        const bool is_generic_candidate =
            !is_known_target_node &&
            old_target_id != 0 &&
            looks_like_action_descriptor(descriptor);
        if ((is_known_target_node || is_generic_candidate) &&
            node_target_id == old_target_id) {
            write_u32(block, node_offset + 0x10, static_cast<uint32_t>(fresh_target_id));
            if (is_known_target_node) {
                ++target_patched;
            } else {
                ++target_generic_patched;
            }
        } else if (is_known_target_node) {
            ++target_mismatch;
        }

        if (descriptor == entity_desc) {
            if (patch_entity_vector(
                    block,
                    node_offset,
                    0x50,
                    has_absolute,
                    spawn_x,
                    spawn_y,
                    spawn_z,
                    delta_x,
                    delta_y,
                    delta_z)) {
                ++entity_transform_patched;
            }
        }

        if (descriptor == entity_desc && static_cast<size_t>(node_offset) + 0xB8 <= kSharedBlockCopySize) {
            ++entity_fallback_preserved;
        }

        if (descriptor != place_desc) {
            continue;
        }

        if (prefab_entry_override) {
            write_u64(block, node_offset + 0x18, reinterpret_cast<uint64_t>(prefab_entry_override));
            ++prefab_patched;
        }
        if (orientation_override >= 0) {
            block[node_offset + 0x2C] = static_cast<unsigned char>(orientation_override & 0xff);
            ++orientation_patched;
        }

        if (entity_target_present && node_target_id == old_target_id) {
            ++place_local_preserved;
            continue;
        }

        const int32_t node_x = read_i32(block, node_offset + 0x20);
        const int32_t node_y = read_i32(block, node_offset + 0x24);
        const int32_t node_z = read_i32(block, node_offset + 0x28);
        write_i32(block, node_offset + 0x20, node_x + delta_x);
        write_i32(block, node_offset + 0x24, node_y + delta_y);
        write_i32(block, node_offset + 0x28, node_z + delta_z);
        ++patched;
    }

    if (!entity_target_present && patched == 0 && static_cast<size_t>(snapshot.place_node_offset) + 0x30 <= kSharedBlockCopySize) {
        write_i32(block, snapshot.place_node_offset + 0x20, spawn_x);
        write_i32(block, snapshot.place_node_offset + 0x24, spawn_y);
        write_i32(block, snapshot.place_node_offset + 0x28, spawn_z);
        patched = 1;
    }

    log_line(
        "spawn_request_%s nonce=%s owner=%p queue_original=%p block_original=%p queue_copy=%p block_copy=%p target_registry=%p old_target_id=%u fresh_target_id=%d target_patched=%u target_generic_patched=%u target_mismatch=%u entity_position_patched=%u entity_transform_patched=%u place_local_preserved=%u entity_fallback_preserved=%u prefab_patched=%u orientation_patched=%u owner_busy_before=%u source_offset=%d,%d,%d spawn_offset=%d,%d,%d delta=%d,%d,%d absolute=%d patched=%u cursor=%u count=%u prefab=%p cache_count=%d,%d",
        method,
        nonce ? nonce : "",
        snapshot.owner,
        snapshot.queue_original,
        snapshot.block_original,
        queue,
        block,
        snapshot.target_registry,
        static_cast<unsigned>(old_target_id),
        fresh_target_id,
        static_cast<unsigned>(target_patched),
        static_cast<unsigned>(target_generic_patched),
        static_cast<unsigned>(target_mismatch),
        static_cast<unsigned>(entity_position_patched),
        static_cast<unsigned>(entity_transform_patched),
        static_cast<unsigned>(place_local_preserved),
        static_cast<unsigned>(entity_fallback_preserved),
        static_cast<unsigned>(prefab_patched),
        static_cast<unsigned>(orientation_patched),
        static_cast<unsigned>(safe_read_u8(snapshot.owner, 0x120, 0xff)),
        source_x,
        source_y,
        source_z,
        spawn_x,
        spawn_y,
        spawn_z,
        delta_x,
        delta_y,
        delta_z,
        has_absolute ? 1 : 0,
        static_cast<unsigned>(patched),
        static_cast<unsigned>(snapshot.block_cursor),
        static_cast<unsigned>(snapshot.block_count),
        prefab_entry_override,
        cache_count_before,
        cache_count_after);

    log_shared_nodes(method, 0, block, reinterpret_cast<uintptr_t>(block));

    uint64_t shared_result = 0;
    g_replay_additive_hits = 0;
    if (!call_original_shared_guarded(snapshot.owner, queue, snapshot.arg2, snapshot.arg3, &shared_result)) {
        const uint8_t previous_busy = reset_shared_owner_busy_state(snapshot.owner);
        const long replay_additive_hits = g_replay_additive_hits;
        if (replay_additive_hits > 0) {
            write_status(
                "ok=1 nonce=%s method=%s absolute=%d source_offset=%d,%d,%d spawn_offset=%d,%d,%d patched=%u target_id=%d old_target_id=%u target_patched=%u target_generic_patched=%u target_mismatch=%u entity_transform_patched=%u place_local_preserved=%u entity_fallback_preserved=%u prefab_patched=%u orientation_patched=%u prefab=%p cache_count_before=%d cache_count_after=%d shared_result=%llu owner_busy_after=%u replay_additive_hits=%ld post_exception=1",
                nonce ? nonce : "",
                method,
                has_absolute ? 1 : 0,
                source_x,
                source_y,
                source_z,
                spawn_x,
                spawn_y,
                spawn_z,
                static_cast<unsigned>(patched),
                fresh_target_id,
                static_cast<unsigned>(old_target_id),
                static_cast<unsigned>(target_patched),
                static_cast<unsigned>(target_generic_patched),
                static_cast<unsigned>(target_mismatch),
                static_cast<unsigned>(entity_transform_patched),
                static_cast<unsigned>(place_local_preserved),
                static_cast<unsigned>(entity_fallback_preserved),
                static_cast<unsigned>(prefab_patched),
                static_cast<unsigned>(orientation_patched),
                prefab_entry_override,
                cache_count_before,
                cache_count_after,
                static_cast<unsigned long long>(shared_result),
                static_cast<unsigned>(safe_read_u8(snapshot.owner, 0x120, 0xff)),
                replay_additive_hits);
            log_line(
                "spawn_accepted_%s_after_exception nonce=%s replay_additive_hits=%ld owner_busy_reset_from=%u owner_busy_after=%u",
                method,
                nonce ? nonce : "",
                replay_additive_hits,
                static_cast<unsigned>(previous_busy),
                static_cast<unsigned>(safe_read_u8(snapshot.owner, 0x120, 0xff)));
            return true;
        }

        write_status(
            "ok=0 nonce=%s error=%s_replay_exception exception_code=0x%08lX exception_address=%p exception_rcx=%p exception_rdx=%p exception_r8=%p exception_r9=%p exception_rsp=%p owner_busy_reset_from=%u",
            nonce ? nonce : "",
            method,
            static_cast<unsigned long>(g_last_shared_exception_code),
            g_last_shared_exception_address,
            g_last_shared_exception_rcx,
            g_last_shared_exception_rdx,
            g_last_shared_exception_r8,
            g_last_shared_exception_r9,
            g_last_shared_exception_rsp,
            static_cast<unsigned>(previous_busy));
        log_line(
            "spawn_failed_%s nonce=%s exception code=0x%08lX address=%p rcx=%p rdx=%p r8=%p r9=%p rsp=%p owner_busy_reset_from=%u owner_busy_after=%u",
            method,
            nonce ? nonce : "",
            static_cast<unsigned long>(g_last_shared_exception_code),
            g_last_shared_exception_address,
            g_last_shared_exception_rcx,
            g_last_shared_exception_rdx,
            g_last_shared_exception_r8,
            g_last_shared_exception_r9,
            g_last_shared_exception_rsp,
            static_cast<unsigned>(previous_busy),
            static_cast<unsigned>(safe_read_u8(snapshot.owner, 0x120, 0xff)));
        return true;
    }

    const uint8_t owner_busy_after = safe_read_u8(snapshot.owner, 0x120, 0xff);
    if (shared_result == 0) {
        const long replay_additive_hits = g_replay_additive_hits;
        if (replay_additive_hits > 0) {
            write_status(
                "ok=1 nonce=%s method=%s absolute=%d source_offset=%d,%d,%d spawn_offset=%d,%d,%d patched=%u target_id=%d old_target_id=%u target_patched=%u target_generic_patched=%u target_mismatch=%u entity_transform_patched=%u place_local_preserved=%u entity_fallback_preserved=%u prefab_patched=%u orientation_patched=%u prefab=%p cache_count_before=%d cache_count_after=%d shared_result=%llu owner_busy_after=%u replay_additive_hits=%ld zero_result=1",
                nonce ? nonce : "",
                method,
                has_absolute ? 1 : 0,
                source_x,
                source_y,
                source_z,
                spawn_x,
                spawn_y,
                spawn_z,
                static_cast<unsigned>(patched),
                fresh_target_id,
                static_cast<unsigned>(old_target_id),
                static_cast<unsigned>(target_patched),
                static_cast<unsigned>(target_generic_patched),
                static_cast<unsigned>(target_mismatch),
                static_cast<unsigned>(entity_transform_patched),
                static_cast<unsigned>(place_local_preserved),
                static_cast<unsigned>(entity_fallback_preserved),
                static_cast<unsigned>(prefab_patched),
                static_cast<unsigned>(orientation_patched),
                prefab_entry_override,
                cache_count_before,
                cache_count_after,
                static_cast<unsigned long long>(shared_result),
                static_cast<unsigned>(owner_busy_after),
                replay_additive_hits);
            log_line(
                "spawn_accepted_%s_zero_result nonce=%s replay_additive_hits=%ld owner_busy_after=%u",
                method,
                nonce ? nonce : "",
                replay_additive_hits,
                static_cast<unsigned>(owner_busy_after));
            return true;
        }

        write_status(
            "ok=0 nonce=%s error=%s_replay_not_accepted owner_busy_after=%u",
            nonce ? nonce : "",
            method,
            static_cast<unsigned>(owner_busy_after));
        log_line(
            "spawn_failed_%s nonce=%s not_accepted owner_busy_after=%u",
            method,
            nonce ? nonce : "",
            static_cast<unsigned>(owner_busy_after));
        return true;
    }

    write_status(
        "ok=1 nonce=%s method=%s absolute=%d source_offset=%d,%d,%d spawn_offset=%d,%d,%d patched=%u target_id=%d old_target_id=%u target_patched=%u target_generic_patched=%u target_mismatch=%u entity_transform_patched=%u place_local_preserved=%u entity_fallback_preserved=%u prefab_patched=%u orientation_patched=%u prefab=%p cache_count_before=%d cache_count_after=%d shared_result=%llu owner_busy_after=%u",
        nonce ? nonce : "",
        method,
        has_absolute ? 1 : 0,
        source_x,
        source_y,
        source_z,
        spawn_x,
        spawn_y,
        spawn_z,
        static_cast<unsigned>(patched),
        fresh_target_id,
        static_cast<unsigned>(old_target_id),
        static_cast<unsigned>(target_patched),
        static_cast<unsigned>(target_generic_patched),
        static_cast<unsigned>(target_mismatch),
        static_cast<unsigned>(entity_transform_patched),
        static_cast<unsigned>(place_local_preserved),
        static_cast<unsigned>(entity_fallback_preserved),
        static_cast<unsigned>(prefab_patched),
        static_cast<unsigned>(orientation_patched),
        prefab_entry_override,
        cache_count_before,
        cache_count_after,
        static_cast<unsigned long long>(shared_result),
        static_cast<unsigned>(owner_busy_after));
    return true;
}

bool spawn_file_prefab_shared(
    const char* nonce,
    void* owner,
    void* cache_owner,
    const std::string& prefab_path,
    const std::string& prefab_hash_hex,
    void* preferred_target_registry,
    void* place_context,
    int32_t spawn_x,
    int32_t spawn_y,
    int32_t spawn_z,
    int32_t orientation) {
    if (!g_original_shared) {
        write_status("ok=0 nonce=%s error=missing_shared_submit", nonce ? nonce : "");
        return true;
    }
    if (!cache_owner || prefab_path.empty() || (!owner && !place_context)) {
        write_status(
            "ok=0 nonce=%s error=file_spawn_missing_context owner=%p place_context=%p cache=%p path_present=%d",
            nonce ? nonce : "",
            owner,
            place_context,
            cache_owner,
            prefab_path.empty() ? 0 : 1);
        return true;
    }

    void* prefab_entry = nullptr;
    int32_t cache_count_before = -1;
    int32_t cache_count_after = -1;
    bool raw_exception = false;
    bool pending = false;
    if (!materialize_prefab_file(
            prefab_path,
            cache_owner,
            prefab_hash_hex,
            &prefab_entry,
            &cache_count_before,
            &cache_count_after,
            &raw_exception,
            &pending) ||
        !prefab_entry) {
        write_status(
            "ok=0 nonce=%s pending=%d error=%s cache_count_before=%d cache_count_after=%d raw_exception=%d",
            nonce ? nonce : "",
            pending ? 1 : 0,
            pending ? "file_prefab_pending" : "file_prefab_materialize_failed",
            cache_count_before,
            cache_count_after,
            raw_exception ? 1 : 0);
        return true;
    }

    {
        SharedSnapshot template_snapshot{};
        bool loaded_from_disk = false;
        void* replay_owner = owner;
        void* replay_owner_surface = owner;
        bool replay_owner_from_place_context = owner != nullptr;
        const char* replay_owner_source = owner ? "command_owner" : "";
        void* derived_owner = nullptr;
        void* derived_owner_surface = nullptr;
        const char* derived_owner_source = "";
        if (derive_shared_owner_from_place_context(
                place_context,
                &derived_owner,
                &derived_owner_surface,
                &derived_owner_source)) {
            if (!replay_owner) {
                replay_owner = derived_owner;
                replay_owner_surface = derived_owner_surface;
                replay_owner_source = derived_owner_source;
                replay_owner_from_place_context = true;
            }
            log_line(
                "file_shared_derived_owner_from_place_context nonce=%s place_context=%p owner_surface=%p owner=%p source=%s command_owner=%p replay_owner=%p replay_source=%s",
                nonce ? nonce : "",
                place_context,
                derived_owner_surface,
                derived_owner,
                derived_owner_source,
                owner,
                replay_owner,
                replay_owner_source);
        }
        if (!select_shared_template_for_file_spawn(
                replay_owner,
                preferred_target_registry,
                replay_owner_from_place_context,
                &template_snapshot,
                &loaded_from_disk)) {
            write_status(
                "ok=0 nonce=%s error=file_shared_missing_template prefab=%p cache_count_before=%d cache_count_after=%d",
                nonce ? nonce : "",
                prefab_entry,
                cache_count_before,
                cache_count_after);
            log_line(
                "file_spawn_rejected_shared nonce=%s missing_template owner=%p replay_owner=%p place_context=%p owner_from_place_context=%d cache=%p prefab=%p path=%s cache_count=%d,%d",
                nonce ? nonce : "",
                owner,
                replay_owner,
                place_context,
                replay_owner_from_place_context ? 1 : 0,
                cache_owner,
                prefab_entry,
                prefab_path.c_str(),
                cache_count_before,
                cache_count_after);
            return true;
        }

        if (loaded_from_disk) {
            log_line(
                "file_spawn_disk_template_enabled nonce=%s owner=%p replay_owner=%p place_context=%p cache=%p prefab=%p path=%s cache_count=%d,%d",
                nonce ? nonce : "",
                owner,
                replay_owner,
                place_context,
                cache_owner,
                prefab_entry,
                prefab_path.c_str(),
                cache_count_before,
                cache_count_after);
        }

        log_line(
            "file_spawn_using_template nonce=%s loaded_from_disk=%d owner=%p registry=%p place_node=0x%X entity_node=0x%X prefab=%p path=%s target=%d,%d,%d orientation=%d",
            nonce ? nonce : "",
            loaded_from_disk ? 1 : 0,
            template_snapshot.owner,
            template_snapshot.target_registry,
            static_cast<unsigned>(template_snapshot.place_node_offset),
            static_cast<unsigned>(template_snapshot.entity_node_offset),
            prefab_entry,
            prefab_path.c_str(),
            spawn_x,
            spawn_y,
            spawn_z,
            orientation);
        return spawn_shared_snapshot(
            nonce,
            template_snapshot,
            "file_shared",
            0,
            0,
            0,
            true,
            spawn_x,
            spawn_y,
            spawn_z,
            prefab_entry,
            orientation,
            cache_count_before,
            cache_count_after);
    }

    void* target_registry = preferred_target_registry;
    if (!target_registry) {
        std::lock_guard<std::mutex> lock(g_snapshot_mutex);
        target_registry = g_latest_target_registry;
    }

    if (!target_registry) {
        write_status(
            "ok=0 nonce=%s error=file_shared_missing_target_registry prefab=%p cache_count_before=%d cache_count_after=%d",
            nonce ? nonce : "",
            prefab_entry,
            cache_count_before,
            cache_count_after);
        log_line(
            "file_spawn_rejected_shared nonce=%s missing_target_registry owner=%p cache=%p prefab=%p path=%s cache_count=%d,%d",
            nonce ? nonce : "",
            owner,
            cache_owner,
            prefab_entry,
            prefab_path.c_str(),
            cache_count_before,
            cache_count_after);
        log_prefab_entry_fields("file_rejected", "missing_target_registry", prefab_entry);
        return true;
    }

    int32_t fresh_target_id = -1;
    bool used_registry = false;
    if (allocate_fresh_target_id(target_registry, &fresh_target_id)) {
        used_registry = true;
    } else {
        write_status(
            "ok=0 nonce=%s error=file_shared_target_allocator_unavailable registry=%p prefab=%p cache_count_before=%d cache_count_after=%d",
            nonce ? nonce : "",
            target_registry,
            prefab_entry,
            cache_count_before,
            cache_count_after);
        log_line(
            "file_spawn_rejected_shared nonce=%s target_allocator_unavailable registry=%p owner=%p cache=%p prefab=%p path=%s cache_count=%d,%d",
            nonce ? nonce : "",
            target_registry,
            owner,
            cache_owner,
            prefab_entry,
            prefab_path.c_str(),
            cache_count_before,
            cache_count_after);
        log_prefab_entry_fields("file_rejected", "target_allocator_unavailable", prefab_entry);
        return true;
    }

    auto* queue = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, kSharedQueueCopySize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    auto* block = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, kSharedBlockCopySize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    if (!queue || !block) {
        write_status("ok=0 nonce=%s error=file_shared_alloc_failed", nonce ? nonce : "");
        log_line(
            "file_spawn_failed nonce=%s alloc queue=%p block=%p gle=%lu",
            nonce ? nonce : "",
            queue,
            block,
            GetLastError());
        return true;
    }

    prepare_shared_queue_for_replay(queue, block, 2);

    write_u16(block, 0x10, 4);
    write_u16(block, 0x12, 0xF8);
    write_u16(block, 0x14, 2);
    write_u16(block, 0x18, 0xC8);
    write_u16(block, 0x1A, 0x08);

    constexpr uint16_t entity_node = 0x20;
    constexpr uint16_t place_node = 0xE0;
    write_u64(block, entity_node + 0x00, runtime_entity_placement_descriptor());
    write_u64(block, entity_node + 0x08, 1);
    write_u32(block, entity_node + 0x10, static_cast<uint32_t>(fresh_target_id));
    write_u64(block, entity_node + 0x18, 0);
    write_i32(block, entity_node + 0x20, spawn_x);
    write_i32(block, entity_node + 0x24, spawn_y);
    write_i32(block, entity_node + 0x28, spawn_z);
    block[entity_node + 0x2C] = 0;
    write_f64(block, entity_node + 0x50, static_cast<double>(spawn_x));
    write_f64(block, entity_node + 0x58, static_cast<double>(spawn_y));
    write_f64(block, entity_node + 0x60, static_cast<double>(spawn_z));
    write_i32(block, entity_node + 0xB0, 1);
    write_i32(block, entity_node + 0xB4, 0);

    write_u64(block, place_node + 0x00, runtime_place_prefab_descriptor());
    write_u64(block, place_node + 0x08, 0);
    write_u32(block, place_node + 0x10, static_cast<uint32_t>(fresh_target_id));
    write_u64(block, place_node + 0x18, reinterpret_cast<uint64_t>(prefab_entry));
    write_i32(block, place_node + 0x20, 0);
    write_i32(block, place_node + 0x24, 0);
    write_i32(block, place_node + 0x28, 0);
    block[place_node + 0x2C] = static_cast<unsigned char>(orientation & 0xff);

    log_line(
        "file_spawn_request_shared nonce=%s owner=%p cache=%p prefab=%p path=%s queue=%p block=%p target_registry=%p target_id=%d used_registry=%d spawn_offset=%d,%d,%d orientation=%d cache_count=%d,%d",
        nonce ? nonce : "",
        owner,
        cache_owner,
        prefab_entry,
        prefab_path.c_str(),
        queue,
        block,
        target_registry,
        fresh_target_id,
        used_registry ? 1 : 0,
        spawn_x,
        spawn_y,
        spawn_z,
        orientation,
        cache_count_before,
        cache_count_after);
    log_shared_nodes("file_shared", 0, block, reinterpret_cast<uintptr_t>(block));

    uint64_t shared_result = 0;
    g_replay_additive_hits = 0;
    if (!call_original_shared_guarded(owner, queue, 0, 0, &shared_result)) {
        const uint8_t previous_busy = reset_shared_owner_busy_state(owner);
        const long replay_additive_hits = g_replay_additive_hits;
        if (replay_additive_hits > 0) {
            write_status(
                "ok=1 nonce=%s method=file_shared spawn_offset=%d,%d,%d target_id=%d used_registry=%d prefab=%p cache_count_before=%d cache_count_after=%d replay_additive_hits=%ld post_exception=1 owner_busy_reset_from=%u",
                nonce ? nonce : "",
                spawn_x,
                spawn_y,
                spawn_z,
                fresh_target_id,
                used_registry ? 1 : 0,
                prefab_entry,
                cache_count_before,
                cache_count_after,
                replay_additive_hits,
                static_cast<unsigned>(previous_busy));
            log_line(
                "file_spawn_accepted_after_exception nonce=%s replay_additive_hits=%ld owner_busy_reset_from=%u",
                nonce ? nonce : "",
                replay_additive_hits,
                static_cast<unsigned>(previous_busy));
            return true;
        }

        write_status(
            "ok=0 nonce=%s error=file_shared_exception exception_code=0x%08lX exception_address=%p exception_rcx=%p exception_rdx=%p exception_r8=%p exception_r9=%p exception_rsp=%p target_id=%d used_registry=%d owner_busy_reset_from=%u",
            nonce ? nonce : "",
            static_cast<unsigned long>(g_last_shared_exception_code),
            g_last_shared_exception_address,
            g_last_shared_exception_rcx,
            g_last_shared_exception_rdx,
            g_last_shared_exception_r8,
            g_last_shared_exception_r9,
            g_last_shared_exception_rsp,
            fresh_target_id,
            used_registry ? 1 : 0,
            static_cast<unsigned>(previous_busy));
        log_line(
            "file_spawn_failed_shared nonce=%s exception code=0x%08lX address=%p rcx=%p rdx=%p r8=%p r9=%p rsp=%p target_id=%d used_registry=%d owner_busy_reset_from=%u",
            nonce ? nonce : "",
            static_cast<unsigned long>(g_last_shared_exception_code),
            g_last_shared_exception_address,
            g_last_shared_exception_rcx,
            g_last_shared_exception_rdx,
            g_last_shared_exception_r8,
            g_last_shared_exception_r9,
            g_last_shared_exception_rsp,
            fresh_target_id,
            used_registry ? 1 : 0,
            static_cast<unsigned>(previous_busy));
        return true;
    }

    const long replay_additive_hits = g_replay_additive_hits;
    const uint8_t owner_busy_after = safe_read_u8(owner, 0x120, 0xff);
    if (shared_result == 0 && replay_additive_hits <= 0) {
        write_status(
            "ok=0 nonce=%s error=file_shared_not_accepted target_id=%d used_registry=%d owner_busy_after=%u",
            nonce ? nonce : "",
            fresh_target_id,
            used_registry ? 1 : 0,
            static_cast<unsigned>(owner_busy_after));
        log_line(
            "file_spawn_failed_shared nonce=%s not_accepted target_id=%d used_registry=%d owner_busy_after=%u",
            nonce ? nonce : "",
            fresh_target_id,
            used_registry ? 1 : 0,
            static_cast<unsigned>(owner_busy_after));
        return true;
    }

    write_status(
        "ok=1 nonce=%s method=file_shared spawn_offset=%d,%d,%d target_id=%d used_registry=%d prefab=%p cache_count_before=%d cache_count_after=%d shared_result=%llu replay_additive_hits=%ld owner_busy_after=%u",
        nonce ? nonce : "",
        spawn_x,
        spawn_y,
        spawn_z,
        fresh_target_id,
        used_registry ? 1 : 0,
        prefab_entry,
        cache_count_before,
        cache_count_after,
        static_cast<unsigned long long>(shared_result),
        replay_additive_hits,
        static_cast<unsigned>(owner_busy_after));
    log_line(
        "file_spawn_accepted_shared nonce=%s result=%llu replay_additive_hits=%ld target_id=%d used_registry=%d",
        nonce ? nonce : "",
        static_cast<unsigned long long>(shared_result),
        replay_additive_hits,
        fresh_target_id,
        used_registry ? 1 : 0);
    return true;
}

struct Control {
    bool duplicate = false;
    int32_t y_offset = kDefaultYOffset;
    long limit = kDefaultDuplicateLimit;
};

bool parse_int_after(const char* buffer, const char* key, int32_t* value) {
    const char* found = std::strstr(buffer, key);
    if (!found) {
        return false;
    }

    char* end = nullptr;
    const long parsed = std::strtol(found + std::strlen(key), &end, 10);
    if (end == found + std::strlen(key)) {
        return false;
    }

    *value = static_cast<int32_t>(parsed);
    return true;
}

bool parse_u64_after(const char* buffer, const char* key, uint64_t* value) {
    const char* found = std::strstr(buffer, key);
    if (!found) {
        return false;
    }

    char* end = nullptr;
    const unsigned long long parsed = std::strtoull(found + std::strlen(key), &end, 0);
    if (end == found + std::strlen(key)) {
        return false;
    }

    *value = static_cast<uint64_t>(parsed);
    return true;
}

bool read_text_file(const wchar_t* path, char* buffer, size_t len) {
    if (!buffer || len == 0) {
        return false;
    }

    FILE* file = nullptr;
    _wfopen_s(&file, path, L"rb");
    if (!file) {
        buffer[0] = 0;
        return false;
    }

    const size_t bytes = std::fread(buffer, 1, len - 1, file);
    std::fclose(file);
    buffer[bytes] = 0;
    return bytes > 0;
}

std::string parse_string_after(const char* buffer, const char* key) {
    const char* found = std::strstr(buffer, key);
    if (!found) {
        return {};
    }

    const char* start = found + std::strlen(key);
    const char* end = start;
    while (*end && *end != '\r' && *end != '\n') {
        ++end;
    }
    return std::string(start, static_cast<size_t>(end - start));
}

Control read_control() {
    Control control{};
    char buffer[2048]{};
    if (!read_text_file(kControlPath, buffer, sizeof(buffer))) {
        return control;
    }

    control.duplicate = std::strstr(buffer, "duplicate=1") != nullptr;
    parse_int_after(buffer, "y_offset=", &control.y_offset);
    int32_t parsed_limit = 0;
    if (parse_int_after(buffer, "limit=", &parsed_limit) && parsed_limit > 0) {
        control.limit = parsed_limit;
    }
    return control;
}

void capture_latest_global(void* manager, void* bundle_or_archive, void* params, void* context, const unsigned char* params_copy) {
    AdditiveSnapshot snapshot{};
    snapshot.has = true;
    snapshot.manager = manager;
    snapshot.bundle_or_archive = bundle_or_archive;
    snapshot.context_original = context;
    std::memcpy(snapshot.params, params_copy, kParamsSize);
    safe_copy(snapshot.context, context, kContextCopySize);

    {
        std::lock_guard<std::mutex> lock(g_snapshot_mutex);
        g_latest_global = snapshot;
    }
}

void capture_latest_action(
    void* owner,
    void* request,
    void* placement,
    const unsigned char* request_copy,
    const unsigned char* placement_copy) {
    ActionSnapshot snapshot{};
    snapshot.has = true;
    snapshot.owner = owner;
    snapshot.request_original = request;
    snapshot.placement_original = placement;
    std::memcpy(snapshot.request, request_copy, kActionParamCopySize);
    std::memcpy(snapshot.placement, placement_copy, kActionParamCopySize);

    {
        std::lock_guard<std::mutex> lock(g_snapshot_mutex);
        g_latest_action = snapshot;
    }
}

bool call_original_action_guarded(void* owner, void* request, void* placement) {
    __try {
        g_action_replay_in_progress = true;
        g_original_action(owner, request, placement);
        g_action_replay_in_progress = false;
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        g_action_replay_in_progress = false;
        return false;
    }
}

bool spawn_action_from_latest(
    const char* nonce,
    int32_t x_offset,
    int32_t y_offset,
    int32_t z_offset,
    bool has_absolute,
    int32_t absolute_x,
    int32_t absolute_y,
    int32_t absolute_z) {
    if (!g_original_action) {
        return false;
    }

    ActionSnapshot snapshot{};
    {
        std::lock_guard<std::mutex> lock(g_snapshot_mutex);
        snapshot = g_latest_action;
    }

    if (!snapshot.has || !snapshot.owner) {
        return false;
    }

    alignas(16) unsigned char request[kActionParamCopySize]{};
    alignas(16) unsigned char placement[kActionParamCopySize]{};
    std::memcpy(request, snapshot.request, sizeof(request));
    std::memcpy(placement, snapshot.placement, sizeof(placement));

    const int32_t x = read_i32(placement, 0x08);
    const int32_t y = read_i32(placement, 0x0C);
    const int32_t z = read_i32(placement, 0x10);
    const int32_t spawn_x = has_absolute ? absolute_x : x + x_offset;
    const int32_t spawn_y = has_absolute ? absolute_y : y + y_offset;
    const int32_t spawn_z = has_absolute ? absolute_z : z + z_offset;
    write_i32(placement, 0x08, spawn_x);
    write_i32(placement, 0x0C, spawn_y);
    write_i32(placement, 0x10, spawn_z);

    log_line(
        "spawn_request_action nonce=%s owner=%p request_original=%p placement_original=%p source_offset=%d,%d,%d spawn_offset=%d,%d,%d delta=%d,%d,%d absolute=%d request0=%p placement0=%p",
        nonce ? nonce : "",
        snapshot.owner,
        snapshot.request_original,
        snapshot.placement_original,
        x,
        y,
        z,
        spawn_x,
        spawn_y,
        spawn_z,
        x_offset,
        y_offset,
        z_offset,
        has_absolute ? 1 : 0,
        reinterpret_cast<void*>(read_u64(request, 0x00)),
        reinterpret_cast<void*>(read_u64(placement, 0x00)));

    if (!call_original_action_guarded(snapshot.owner, request, placement)) {
        write_status("ok=0 nonce=%s error=action_replay_exception", nonce ? nonce : "");
        log_line("spawn_failed_action nonce=%s exception", nonce ? nonce : "");
        return true;
    }

    write_status(
        "ok=1 nonce=%s method=action absolute=%d source_offset=%d,%d,%d spawn_offset=%d,%d,%d",
        nonce ? nonce : "",
        has_absolute ? 1 : 0,
        x,
        y,
        z,
        spawn_x,
        spawn_y,
        spawn_z);
    return true;
}

bool spawn_shared_from_latest(
    const char* nonce,
    int32_t x_offset,
    int32_t y_offset,
    int32_t z_offset,
    bool has_absolute,
    int32_t absolute_x,
    int32_t absolute_y,
    int32_t absolute_z) {
    if (!g_original_shared) {
        return false;
    }

    SharedSnapshot snapshot{};
    {
        std::lock_guard<std::mutex> lock(g_snapshot_mutex);
        snapshot = g_latest_shared;
    }

    if (!snapshot.has || !snapshot.owner || snapshot.place_node_offset == 0) {
        return false;
    }

    const uint32_t old_target_id = read_u32(snapshot.block, snapshot.place_node_offset + 0x10);
    int32_t fresh_target_id = -1;
    if (!allocate_fresh_target_id(snapshot.target_registry, &fresh_target_id)) {
        write_status("ok=0 nonce=%s error=target_allocator_unavailable", nonce ? nonce : "");
        log_line(
            "spawn_failed_shared nonce=%s target_allocator_unavailable registry=%p old_target_id=%u snapshot_target_id=%d installed=%d",
            nonce ? nonce : "",
            snapshot.target_registry,
            static_cast<unsigned>(old_target_id),
            snapshot.target_id,
            g_target_allocator_installed.load() ? 1 : 0);
        return true;
    }

    auto* queue = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, kSharedQueueCopySize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    auto* block = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, kSharedBlockCopySize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    if (!queue || !block) {
        write_status("ok=0 nonce=%s error=shared_replay_alloc_failed", nonce ? nonce : "");
        log_line(
            "spawn_failed_shared nonce=%s alloc queue=%p block=%p gle=%lu",
            nonce ? nonce : "",
            queue,
            block,
            GetLastError());
        return true;
    }

    std::memcpy(queue, snapshot.queue, kSharedQueueCopySize);
    std::memcpy(block, snapshot.block, kSharedBlockCopySize);

    prepare_shared_queue_for_replay(queue, block, snapshot.block_count);
    write_u64(block, 0x00, 0);
    write_u64(block, 0x08, 0);

    const int32_t source_x = snapshot.source_x;
    const int32_t source_y = snapshot.source_y;
    const int32_t source_z = snapshot.source_z;
    const int32_t spawn_x = has_absolute ? absolute_x : source_x + x_offset;
    const int32_t spawn_y = has_absolute ? absolute_y : source_y + y_offset;
    const int32_t spawn_z = has_absolute ? absolute_z : source_z + z_offset;
    const int32_t delta_x = spawn_x - source_x;
    const int32_t delta_y = spawn_y - source_y;
    const int32_t delta_z = spawn_z - source_z;

    const uintptr_t place_desc = runtime_place_prefab_descriptor();
    const uintptr_t entity_mutation_desc = runtime_entity_mutation_descriptor();
    const uintptr_t entity_desc = runtime_entity_placement_descriptor();
    const uint16_t count = read_u16(block, 0x14);
    const uint16_t limit = count > kSharedNodeScanLimit ? kSharedNodeScanLimit : count;
    uint16_t patched = 0;
    uint16_t target_patched = 0;
    uint16_t target_generic_patched = 0;
    uint16_t entity_position_patched = 0;
    uint16_t entity_transform_patched = 0;
    uint16_t place_local_preserved = 0;
    uint16_t entity_fallback_preserved = 0;
    uint16_t target_mismatch = 0;
    bool entity_target_present = false;
    for (uint16_t i = 0; i < limit; ++i) {
        uint16_t entry_offset = 0;
        uint16_t node_offset = 0;
        if (!shared_node_offset_by_index(block, kSharedBlockCopySize, i, &entry_offset, &node_offset)) {
            continue;
        }
        if (static_cast<size_t>(node_offset) + 0x30 > kSharedBlockCopySize) {
            continue;
        }

        if (read_u64(block, node_offset) == entity_desc &&
            read_u32(block, node_offset + 0x10) == old_target_id) {
            entity_target_present = true;
            break;
        }
    }

    for (uint16_t i = 0; i < limit; ++i) {
        uint16_t entry_offset = 0;
        uint16_t node_offset = 0;
        if (!shared_node_offset_by_index(block, kSharedBlockCopySize, i, &entry_offset, &node_offset)) {
            continue;
        }
        if (static_cast<size_t>(node_offset) + 0x30 > kSharedBlockCopySize) {
            continue;
        }

        const uint64_t descriptor = read_u64(block, node_offset);
        const uint32_t node_target_id = read_u32(block, node_offset + 0x10);
        const bool is_known_target_node =
            descriptor == place_desc ||
            descriptor == entity_desc ||
            descriptor == entity_mutation_desc;
        const bool is_generic_candidate =
            !is_known_target_node &&
            old_target_id != 0 &&
            looks_like_action_descriptor(descriptor);
        if ((is_known_target_node || is_generic_candidate) &&
            node_target_id == old_target_id) {
            write_u32(block, node_offset + 0x10, static_cast<uint32_t>(fresh_target_id));
            if (is_known_target_node) {
                ++target_patched;
            } else {
                ++target_generic_patched;
            }
        } else if (is_known_target_node) {
            ++target_mismatch;
        }

        if (descriptor == entity_desc) {
            if (patch_entity_vector(
                    block,
                    node_offset,
                    0x50,
                    has_absolute,
                    spawn_x,
                    spawn_y,
                    spawn_z,
                    delta_x,
                    delta_y,
                    delta_z)) {
                ++entity_transform_patched;
            }
        }

        if (descriptor == entity_desc && static_cast<size_t>(node_offset) + 0xB8 <= kSharedBlockCopySize) {
            ++entity_fallback_preserved;
        }

        if (descriptor != place_desc) {
            continue;
        }

        if (entity_target_present && node_target_id == old_target_id) {
            ++place_local_preserved;
            continue;
        }

        const int32_t node_x = read_i32(block, node_offset + 0x20);
        const int32_t node_y = read_i32(block, node_offset + 0x24);
        const int32_t node_z = read_i32(block, node_offset + 0x28);
        write_i32(block, node_offset + 0x20, node_x + delta_x);
        write_i32(block, node_offset + 0x24, node_y + delta_y);
        write_i32(block, node_offset + 0x28, node_z + delta_z);
        ++patched;
    }

    if (!entity_target_present && patched == 0 && static_cast<size_t>(snapshot.place_node_offset) + 0x30 <= kSharedBlockCopySize) {
        write_i32(block, snapshot.place_node_offset + 0x20, spawn_x);
        write_i32(block, snapshot.place_node_offset + 0x24, spawn_y);
        write_i32(block, snapshot.place_node_offset + 0x28, spawn_z);
        patched = 1;
    }

    log_line(
        "spawn_request_shared nonce=%s owner=%p queue_original=%p block_original=%p queue_copy=%p block_copy=%p target_registry=%p old_target_id=%u fresh_target_id=%d target_patched=%u target_generic_patched=%u target_mismatch=%u entity_position_patched=%u entity_transform_patched=%u place_local_preserved=%u entity_fallback_preserved=%u owner_busy_before=%u source_offset=%d,%d,%d spawn_offset=%d,%d,%d delta=%d,%d,%d absolute=%d patched=%u cursor=%u count=%u",
        nonce ? nonce : "",
        snapshot.owner,
        snapshot.queue_original,
        snapshot.block_original,
        queue,
        block,
        snapshot.target_registry,
        static_cast<unsigned>(old_target_id),
        fresh_target_id,
        static_cast<unsigned>(target_patched),
        static_cast<unsigned>(target_generic_patched),
        static_cast<unsigned>(target_mismatch),
        static_cast<unsigned>(entity_position_patched),
        static_cast<unsigned>(entity_transform_patched),
        static_cast<unsigned>(place_local_preserved),
        static_cast<unsigned>(entity_fallback_preserved),
        static_cast<unsigned>(safe_read_u8(snapshot.owner, 0x120, 0xff)),
        source_x,
        source_y,
        source_z,
        spawn_x,
        spawn_y,
        spawn_z,
        delta_x,
        delta_y,
        delta_z,
        has_absolute ? 1 : 0,
        static_cast<unsigned>(patched),
        static_cast<unsigned>(snapshot.block_cursor),
        static_cast<unsigned>(snapshot.block_count));

    log_shared_nodes("shared_replay", 0, block, reinterpret_cast<uintptr_t>(block));

    uint64_t shared_result = 0;
    g_replay_additive_hits = 0;
    if (!call_original_shared_guarded(snapshot.owner, queue, snapshot.arg2, snapshot.arg3, &shared_result)) {
        const uint8_t previous_busy = reset_shared_owner_busy_state(snapshot.owner);
        const long replay_additive_hits = g_replay_additive_hits;
        if (replay_additive_hits > 0) {
            write_status(
                "ok=1 nonce=%s method=shared absolute=%d source_offset=%d,%d,%d spawn_offset=%d,%d,%d patched=%u target_id=%d old_target_id=%u target_patched=%u target_generic_patched=%u target_mismatch=%u entity_transform_patched=%u place_local_preserved=%u entity_fallback_preserved=%u shared_result=%llu owner_busy_after=%u replay_additive_hits=%ld post_exception=1",
                nonce ? nonce : "",
                has_absolute ? 1 : 0,
                source_x,
                source_y,
                source_z,
                spawn_x,
                spawn_y,
                spawn_z,
                static_cast<unsigned>(patched),
                fresh_target_id,
                static_cast<unsigned>(old_target_id),
                static_cast<unsigned>(target_patched),
                static_cast<unsigned>(target_generic_patched),
                static_cast<unsigned>(target_mismatch),
                static_cast<unsigned>(entity_transform_patched),
                static_cast<unsigned>(place_local_preserved),
                static_cast<unsigned>(entity_fallback_preserved),
                static_cast<unsigned long long>(shared_result),
                static_cast<unsigned>(safe_read_u8(snapshot.owner, 0x120, 0xff)),
                replay_additive_hits);
            log_line(
                "spawn_accepted_shared_after_exception nonce=%s replay_additive_hits=%ld owner_busy_reset_from=%u owner_busy_after=%u",
                nonce ? nonce : "",
                replay_additive_hits,
                static_cast<unsigned>(previous_busy),
                static_cast<unsigned>(safe_read_u8(snapshot.owner, 0x120, 0xff)));
            return true;
        }

        write_status(
            "ok=0 nonce=%s error=shared_replay_exception exception_code=0x%08lX exception_address=%p exception_rcx=%p exception_rdx=%p exception_r8=%p exception_r9=%p exception_rsp=%p owner_busy_reset_from=%u",
            nonce ? nonce : "",
            static_cast<unsigned long>(g_last_shared_exception_code),
            g_last_shared_exception_address,
            g_last_shared_exception_rcx,
            g_last_shared_exception_rdx,
            g_last_shared_exception_r8,
            g_last_shared_exception_r9,
            g_last_shared_exception_rsp,
            static_cast<unsigned>(previous_busy));
        log_line(
            "spawn_failed_shared nonce=%s exception code=0x%08lX address=%p rcx=%p rdx=%p r8=%p r9=%p rsp=%p owner_busy_reset_from=%u owner_busy_after=%u",
            nonce ? nonce : "",
            static_cast<unsigned long>(g_last_shared_exception_code),
            g_last_shared_exception_address,
            g_last_shared_exception_rcx,
            g_last_shared_exception_rdx,
            g_last_shared_exception_r8,
            g_last_shared_exception_r9,
            g_last_shared_exception_rsp,
            static_cast<unsigned>(previous_busy),
            static_cast<unsigned>(safe_read_u8(snapshot.owner, 0x120, 0xff)));
        return true;
    }

    const uint8_t owner_busy_after = safe_read_u8(snapshot.owner, 0x120, 0xff);
    if (shared_result == 0) {
        const long replay_additive_hits = g_replay_additive_hits;
        if (replay_additive_hits > 0) {
            write_status(
                "ok=1 nonce=%s method=shared absolute=%d source_offset=%d,%d,%d spawn_offset=%d,%d,%d patched=%u target_id=%d old_target_id=%u target_patched=%u target_generic_patched=%u target_mismatch=%u entity_transform_patched=%u place_local_preserved=%u entity_fallback_preserved=%u shared_result=%llu owner_busy_after=%u replay_additive_hits=%ld zero_result=1",
                nonce ? nonce : "",
                has_absolute ? 1 : 0,
                source_x,
                source_y,
                source_z,
                spawn_x,
                spawn_y,
                spawn_z,
                static_cast<unsigned>(patched),
                fresh_target_id,
                static_cast<unsigned>(old_target_id),
                static_cast<unsigned>(target_patched),
                static_cast<unsigned>(target_generic_patched),
                static_cast<unsigned>(target_mismatch),
                static_cast<unsigned>(entity_transform_patched),
                static_cast<unsigned>(place_local_preserved),
                static_cast<unsigned>(entity_fallback_preserved),
                static_cast<unsigned long long>(shared_result),
                static_cast<unsigned>(owner_busy_after),
                replay_additive_hits);
            log_line(
                "spawn_accepted_shared_zero_result nonce=%s replay_additive_hits=%ld owner_busy_after=%u",
                nonce ? nonce : "",
                replay_additive_hits,
                static_cast<unsigned>(owner_busy_after));
            return true;
        }

        write_status(
            "ok=0 nonce=%s error=shared_replay_not_accepted owner_busy_after=%u",
            nonce ? nonce : "",
            static_cast<unsigned>(owner_busy_after));
        log_line(
            "spawn_failed_shared nonce=%s not_accepted owner_busy_after=%u",
            nonce ? nonce : "",
            static_cast<unsigned>(owner_busy_after));
        return true;
    }

    write_status(
        "ok=1 nonce=%s method=shared absolute=%d source_offset=%d,%d,%d spawn_offset=%d,%d,%d patched=%u target_id=%d old_target_id=%u target_patched=%u target_generic_patched=%u target_mismatch=%u entity_transform_patched=%u place_local_preserved=%u entity_fallback_preserved=%u shared_result=%llu owner_busy_after=%u",
        nonce ? nonce : "",
        has_absolute ? 1 : 0,
        source_x,
        source_y,
        source_z,
        spawn_x,
        spawn_y,
        spawn_z,
        static_cast<unsigned>(patched),
        fresh_target_id,
        static_cast<unsigned>(old_target_id),
        static_cast<unsigned>(target_patched),
        static_cast<unsigned>(target_generic_patched),
        static_cast<unsigned>(target_mismatch),
        static_cast<unsigned>(entity_transform_patched),
        static_cast<unsigned>(place_local_preserved),
        static_cast<unsigned>(entity_fallback_preserved),
        static_cast<unsigned long long>(shared_result),
        static_cast<unsigned>(owner_busy_after));
    return true;
}

bool seed_latest_from_command(const char* buffer) {
    uint64_t manager = 0;
    uint64_t bundle = 0;
    uint64_t global = 0;
    if (!parse_u64_after(buffer, "manager=", &manager) ||
        !parse_u64_after(buffer, "bundle=", &bundle) ||
        !parse_u64_after(buffer, "global=", &global)) {
        return false;
    }

    int32_t source_x = 0;
    int32_t source_y = 0;
    int32_t source_z = 0;
    int32_t orientation = 16;
    int32_t brick_grid = 1;
    int32_t flag24 = 0;
    int32_t flag25 = 0;
    int32_t flag26 = 1;
    parse_int_after(buffer, "source_x=", &source_x);
    parse_int_after(buffer, "source_y=", &source_y);
    parse_int_after(buffer, "source_z=", &source_z);
    parse_int_after(buffer, "orientation=", &orientation);
    parse_int_after(buffer, "brick_grid=", &brick_grid);
    parse_int_after(buffer, "flag24=", &flag24);
    parse_int_after(buffer, "flag25=", &flag25);
    parse_int_after(buffer, "flag26=", &flag26);

    AdditiveSnapshot snapshot{};
    snapshot.has = true;
    snapshot.manager = reinterpret_cast<void*>(manager);
    snapshot.bundle_or_archive = reinterpret_cast<void*>(bundle);
    snapshot.context_original = nullptr;
    write_u64(snapshot.params, 0x00, global);
    write_i32(snapshot.params, 0x08, source_x);
    write_i32(snapshot.params, 0x0C, source_y);
    write_i32(snapshot.params, 0x10, source_z);
    snapshot.params[0x14] = static_cast<unsigned char>(orientation & 0xff);
    write_u64(snapshot.params, 0x18, 0);
    write_i32(snapshot.params, 0x20, brick_grid);
    snapshot.params[0x24] = static_cast<unsigned char>(flag24 & 0xff);
    snapshot.params[0x25] = static_cast<unsigned char>(flag25 & 0xff);
    snapshot.params[0x26] = static_cast<unsigned char>(flag26 & 0xff);

    {
        std::lock_guard<std::mutex> lock(g_snapshot_mutex);
        g_latest_global = snapshot;
    }

    log_line(
        "seeded_global_from_command manager=%p bundle=%p global=%p source_offset=%d,%d,%d orient=%d brick_grid=%d flags=%d,%d,%d",
        snapshot.manager,
        snapshot.bundle_or_archive,
        reinterpret_cast<void*>(global),
        source_x,
        source_y,
        source_z,
        orientation,
        brick_grid,
        flag24,
        flag25,
        flag26);
    return true;
}

void spawn_from_latest(
    const char* nonce,
    int32_t x_offset,
    int32_t y_offset,
    int32_t z_offset,
    bool has_absolute,
    int32_t absolute_x,
    int32_t absolute_y,
    int32_t absolute_z) {
    if (!g_outer_additive) {
        write_status("ok=0 nonce=%s error=missing_outer_additive", nonce ? nonce : "");
        log_line("spawn_failed nonce=%s missing_outer_additive", nonce ? nonce : "");
        return;
    }

    AdditiveSnapshot snapshot{};
    {
        std::lock_guard<std::mutex> lock(g_snapshot_mutex);
        snapshot = g_latest_global;
    }

    if (!snapshot.has || !snapshot.manager || !snapshot.bundle_or_archive) {
        write_status("ok=0 nonce=%s error=no_global_additive_snapshot", nonce ? nonce : "");
        log_line("spawn_failed nonce=%s no_global_additive_snapshot", nonce ? nonce : "");
        return;
    }

    alignas(16) unsigned char params[kParamsSize]{};
    alignas(16) unsigned char scratch[0x80]{};
    std::memcpy(params, snapshot.params, sizeof(params));

    const int32_t x = read_i32(params, 0x08);
    const int32_t y = read_i32(params, 0x0C);
    const int32_t z = read_i32(params, 0x10);
    const int32_t spawn_x = has_absolute ? absolute_x : x + x_offset;
    const int32_t spawn_y = has_absolute ? absolute_y : y + y_offset;
    const int32_t spawn_z = has_absolute ? absolute_z : z + z_offset;
    write_i32(params, 0x08, spawn_x);
    write_i32(params, 0x0C, spawn_y);
    write_i32(params, 0x10, spawn_z);

    log_line(
        "spawn_request_outer nonce=%s manager=%p bundle=%p context_original=%p source_offset=%d,%d,%d spawn_offset=%d,%d,%d delta=%d,%d,%d absolute=%d",
        nonce ? nonce : "",
        snapshot.manager,
        snapshot.bundle_or_archive,
        snapshot.context_original,
        x,
        y,
        z,
        spawn_x,
        spawn_y,
        spawn_z,
        x_offset,
        y_offset,
        z_offset,
        has_absolute ? 1 : 0);

    g_replay_in_progress = true;
    g_outer_additive(snapshot.manager, snapshot.bundle_or_archive, params, scratch);
    g_replay_in_progress = false;
    write_status(
        "ok=1 nonce=%s method=outer absolute=%d source_offset=%d,%d,%d spawn_offset=%d,%d,%d",
        nonce ? nonce : "",
        has_absolute ? 1 : 0,
        x,
        y,
        z,
        spawn_x,
        spawn_y,
        spawn_z);
}

void process_command_file() {
    const uint64_t now = GetTickCount64();
    if (now - g_last_tick_poll_ms < 100) {
        return;
    }
    g_last_tick_poll_ms = now;

    char buffer[512]{};
    if (!read_text_file(kCommandPath, buffer, sizeof(buffer))) {
        return;
    }

    if (std::strstr(buffer, "spawn=1") == nullptr) {
        return;
    }

    std::string nonce = parse_string_after(buffer, "nonce=");
    if (nonce.empty()) {
        nonce = std::to_string(now);
    }
    if (nonce == g_last_command_nonce) {
        return;
    }
    g_last_command_nonce = nonce;

    int32_t x_offset = 0;
    int32_t y_offset = 520;
    int32_t z_offset = 0;
    parse_int_after(buffer, "x_offset=", &x_offset);
    parse_int_after(buffer, "y_offset=", &y_offset);
    parse_int_after(buffer, "z_offset=", &z_offset);
    int32_t absolute_x = 0;
    int32_t absolute_y = 0;
    int32_t absolute_z = 0;
    const bool has_absolute =
        parse_int_after(buffer, "absolute_x=", &absolute_x) &&
        parse_int_after(buffer, "absolute_y=", &absolute_y) &&
        parse_int_after(buffer, "absolute_z=", &absolute_z);
    const std::string method = parse_string_after(buffer, "method=");
    const std::string prefab_hash = parse_string_after(buffer, "hash=");
    if (method == "place_owner_probe") {
        uint64_t place_context = 0;
        uint64_t owner_offset = 0x988;
        parse_u64_after(buffer, "place_context=", &place_context);
        parse_u64_after(buffer, "owner_offset=", &owner_offset);

        uint64_t place_context_owner = 0;
        const bool read_ok =
            place_context != 0 &&
            owner_offset <= 0x10000 &&
            safe_read_u64_mem(
                reinterpret_cast<void*>(place_context),
                static_cast<size_t>(owner_offset),
                &place_context_owner);
        write_status(
            "ok=%d nonce=%s method=place_owner_probe place_context=%p owner_offset=0x%llX owner=%p",
            read_ok ? 1 : 0,
            nonce.c_str(),
            reinterpret_cast<void*>(place_context),
            static_cast<unsigned long long>(owner_offset),
            reinterpret_cast<void*>(place_context_owner));
        log_line(
            "place_owner_probe nonce=%s ok=%d place_context=%p owner_offset=0x%llX owner=%p",
            nonce.c_str(),
            read_ok ? 1 : 0,
            reinterpret_cast<void*>(place_context),
            static_cast<unsigned long long>(owner_offset),
            reinterpret_cast<void*>(place_context_owner));
        return;
    }

    if (method == "file_shared") {
        uint64_t owner = 0;
        uint64_t cache_owner = 0;
        uint64_t target_registry = 0;
        uint64_t place_context = 0;
        int32_t orientation = 16;
        const std::string prefab_path = parse_string_after(buffer, "prefab_path=");
        parse_u64_after(buffer, "target_registry=", &target_registry);
        parse_u64_after(buffer, "place_context=", &place_context);
        parse_int_after(buffer, "orientation=", &orientation);
        parse_u64_after(buffer, "owner=", &owner);
        if (!parse_u64_after(buffer, "cache_owner=", &cache_owner) ||
            (owner == 0 && place_context == 0) ||
            prefab_path.empty()) {
            write_status(
                "ok=0 nonce=%s error=file_shared_missing_command_fields owner=%p place_context=%p cache=%p path_present=%d",
                nonce.c_str(),
                reinterpret_cast<void*>(owner),
                reinterpret_cast<void*>(place_context),
                reinterpret_cast<void*>(cache_owner),
                prefab_path.empty() ? 0 : 1);
            log_line(
                "file_shared_failed nonce=%s missing_fields owner=%p place_context=%p cache=%p path=%s",
                nonce.c_str(),
                reinterpret_cast<void*>(owner),
                reinterpret_cast<void*>(place_context),
                reinterpret_cast<void*>(cache_owner),
                prefab_path.c_str());
            return;
        }

        const int32_t spawn_x = has_absolute ? absolute_x : x_offset;
        const int32_t spawn_y = has_absolute ? absolute_y : y_offset;
        const int32_t spawn_z = has_absolute ? absolute_z : z_offset;
        spawn_file_prefab_shared(
            nonce.c_str(),
            reinterpret_cast<void*>(owner),
            reinterpret_cast<void*>(cache_owner),
            prefab_path,
            prefab_hash,
            reinterpret_cast<void*>(target_registry),
            reinterpret_cast<void*>(place_context),
            spawn_x,
            spawn_y,
            spawn_z,
            orientation);
        return;
    }

    if (method == "file_seed" || method == "file") {
        uint64_t cache_owner = 0;
        const std::string prefab_path = parse_string_after(buffer, "prefab_path=");
        if (!parse_u64_after(buffer, "cache_owner=", &cache_owner) ||
            prefab_path.empty()) {
            write_status(
                "ok=0 nonce=%s error=file_seed_missing_command_fields cache=%p path_present=%d",
                nonce.c_str(),
                reinterpret_cast<void*>(cache_owner),
                prefab_path.empty() ? 0 : 1);
            log_line(
                "file_seed_failed nonce=%s missing_fields cache=%p path=%s",
                nonce.c_str(),
                reinterpret_cast<void*>(cache_owner),
                prefab_path.c_str());
            return;
        }
        seed_prefab_file(
            nonce.c_str(),
            reinterpret_cast<void*>(cache_owner),
            prefab_path,
            prefab_hash);
        return;
    }

    if (method == "additive") {
        seed_latest_from_command(buffer);
        spawn_from_latest(nonce.c_str(), x_offset, y_offset, z_offset, has_absolute, absolute_x, absolute_y, absolute_z);
        return;
    }

    if (spawn_shared_from_latest(nonce.c_str(), x_offset, y_offset, z_offset, has_absolute, absolute_x, absolute_y, absolute_z)) {
        return;
    }

    if (spawn_action_from_latest(nonce.c_str(), x_offset, y_offset, z_offset, has_absolute, absolute_x, absolute_y, absolute_z)) {
        return;
    }

    write_status("ok=0 nonce=%s error=no_shared_or_action_snapshot additive_fallback_disabled=1", nonce.c_str());
    log_line("spawn_failed nonce=%s no_shared_or_action_snapshot additive_fallback_disabled=1", nonce.c_str());
}

void engine_tick_callback(void*, float) {
    process_command_file();
}

void register_engine_tick_callback() {
    if (g_tick_registered.exchange(true)) {
        return;
    }

    HMODULE ue4ss = GetModuleHandleW(L"UE4SS.dll");
    if (!ue4ss) {
        log_line("engine_tick_register_failed missing UE4SS.dll");
        g_tick_registered = false;
        return;
    }

    auto hook_engine_tick = reinterpret_cast<HookEngineTickFn>(
        GetProcAddress(ue4ss, "?HookEngineTick@Unreal@RC@@YAXXZ"));
    auto register_post = reinterpret_cast<RegisterEngineTickPostCallbackFn>(
        GetProcAddress(
            ue4ss,
            "?RegisterEngineTickPostCallback@Hook@Unreal@RC@@YAXV?$function@$$A6AXPEAVUEngine@Unreal@RC@@M@Z@std@@@Z"));

    if (!hook_engine_tick || !register_post) {
        log_line("engine_tick_register_failed missing_exports hook=%p register=%p", hook_engine_tick, register_post);
        g_tick_registered = false;
        return;
    }

    hook_engine_tick();
    register_post(std::function<void(void*, float)>(engine_tick_callback));
    log_line("engine_tick_registered ue4ss=%p command=%ls status=%ls", ue4ss, kCommandPath, kStatusPath);
}

void append_jump(unsigned char* cursor, void* target) {
    cursor[0] = 0x49;
    cursor[1] = 0xBB;
    const uint64_t address = reinterpret_cast<uint64_t>(target);
    std::memcpy(cursor + 2, &address, sizeof(address));
    cursor[10] = 0x41;
    cursor[11] = 0xFF;
    cursor[12] = 0xE3;
}

bool is_absolute_jump(const unsigned char* target) {
    const bool rax_jump =
        target[0] == 0x48 && target[1] == 0xB8 && target[10] == 0xFF && target[11] == 0xE0;
    const bool r11_jump =
        target[0] == 0x49 && target[1] == 0xBB && target[10] == 0x41 && target[11] == 0xFF &&
        target[12] == 0xE3;
    return rax_jump || r11_jump;
}

bool install_absolute_hook(
    HMODULE module,
    const char* name,
    uintptr_t rva,
    const unsigned char* expected,
    size_t patch_len,
    void* hook,
    void** trampoline_out,
    bool* chained_out) {
    auto* target = reinterpret_cast<unsigned char*>(reinterpret_cast<uintptr_t>(module) + rva);
    const bool matches_original = std::memcmp(target, expected, patch_len) == 0;
    const bool matches_existing_absolute_jump = is_absolute_jump(target);
    if (!matches_original && !matches_existing_absolute_jump) {
        log_line("install_failed_%s prologue_mismatch target=%p", name, target);
        return false;
    }

    auto* trampoline = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, patch_len + kAbsoluteJumpLen, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    if (!trampoline) {
        log_line("install_failed_%s trampoline_alloc gle=%lu", name, GetLastError());
        return false;
    }

    std::memcpy(trampoline, target, patch_len);
    append_jump(trampoline + patch_len, target + patch_len);

    DWORD old_protect = 0;
    if (!VirtualProtect(target, patch_len, PAGE_EXECUTE_READWRITE, &old_protect)) {
        log_line("install_failed_%s protect gle=%lu", name, GetLastError());
        return false;
    }

    unsigned char patch[32]{};
    if (patch_len > sizeof(patch)) {
        log_line("install_failed_%s patch_len_too_large len=%zu", name, patch_len);
        return false;
    }
    append_jump(patch, hook);
    for (size_t i = kAbsoluteJumpLen; i < patch_len; ++i) {
        patch[i] = 0x90;
    }

    std::memcpy(target, patch, patch_len);
    FlushInstructionCache(GetCurrentProcess(), target, patch_len);
    DWORD ignored = 0;
    VirtualProtect(target, patch_len, old_protect, &ignored);

    *trampoline_out = trampoline;
    *chained_out = matches_existing_absolute_jump;
    log_line(
        "installed_%s module=%p target=%p trampoline=%p chain=%d",
        name,
        module,
        target,
        trampoline,
        matches_existing_absolute_jump ? 1 : 0);
    return true;
}

void __fastcall hook_target_allocator(void* registry, int32_t* out_id) {
    int32_t id = -1;
    int32_t next_id = -1;
    if (!emulate_target_allocator(registry, out_id, &id, &next_id)) {
        log_line(
            "target_allocator_skip registry=%p out=%p writable=%d,%d",
            registry,
            out_id,
            registry && is_writable_memory(static_cast<unsigned char*>(registry) + 0x40, sizeof(int32_t)) ? 1 : 0,
            is_writable_memory(out_id, sizeof(int32_t)) ? 1 : 0);
        return;
    }

    {
        std::lock_guard<std::mutex> lock(g_snapshot_mutex);
        g_latest_target_registry = registry;
        g_latest_target_id = id;
    }

    const long hit = g_target_allocator_hits.fetch_add(1) + 1;
    log_line(
        "target_allocator_hit=%ld registry=%p out=%p id=%d next_id=%d",
        hit,
        registry,
        out_id,
        id,
        next_id);
}

void __fastcall hook_action_submitter(void* owner, void* request, void* placement) {
    if (!g_original_action) {
        return;
    }

    alignas(16) unsigned char request_copy[kActionParamCopySize]{};
    alignas(16) unsigned char placement_copy[kActionParamCopySize]{};
    const bool request_ok = safe_copy(request_copy, request, sizeof(request_copy));
    const bool placement_ok = safe_copy(placement_copy, placement, sizeof(placement_copy));
    const long hit = g_action_hits.fetch_add(1) + 1;
    const bool replaying = g_action_replay_in_progress;

    const int32_t placement_x = placement_ok ? read_i32(placement_copy, 0x08) : 0;
    const int32_t placement_y = placement_ok ? read_i32(placement_copy, 0x0C) : 0;
    const int32_t placement_z = placement_ok ? read_i32(placement_copy, 0x10) : 0;
    const uint8_t request_mode = request_ok ? request_copy[0x18] : 0xff;

    log_line(
        "action_hit=%ld owner=%p request=%p placement=%p ok=%d,%d replay=%d request0=%p request_mode=%u placement0=%p placement_offset=%d,%d,%d placement_q18=%p placement_q20=%p",
        hit,
        owner,
        request,
        placement,
        request_ok ? 1 : 0,
        placement_ok ? 1 : 0,
        replaying ? 1 : 0,
        request_ok ? reinterpret_cast<void*>(read_u64(request_copy, 0x00)) : nullptr,
        static_cast<unsigned>(request_mode),
        placement_ok ? reinterpret_cast<void*>(read_u64(placement_copy, 0x00)) : nullptr,
        placement_x,
        placement_y,
        placement_z,
        placement_ok ? reinterpret_cast<void*>(read_u64(placement_copy, 0x18)) : nullptr,
        placement_ok ? reinterpret_cast<void*>(read_u64(placement_copy, 0x20)) : nullptr);

    if (!replaying && request_ok && placement_ok) {
        capture_latest_action(owner, request, placement, request_copy, placement_copy);
        log_line(
            "captured_action owner=%p request=%p placement=%p placement_offset=%d,%d,%d request0=%p placement0=%p",
            owner,
            request,
            placement,
            placement_x,
            placement_y,
            placement_z,
            reinterpret_cast<void*>(read_u64(request_copy, 0x00)),
            reinterpret_cast<void*>(read_u64(placement_copy, 0x00)));
    }

    g_original_action(owner, request, placement);
}

uint64_t __fastcall hook_shared_submit(void* owner, void* queue, uint64_t arg2, uint64_t arg3) {
    if (!g_original_shared) {
        return 0;
    }

    const uintptr_t return_addr = reinterpret_cast<uintptr_t>(_ReturnAddress());
    const uintptr_t caller_va =
        g_module_base != 0 && return_addr >= g_module_base
            ? kImageBase + (return_addr - g_module_base)
            : return_addr;

    alignas(16) unsigned char queue_copy[kSharedQueueCopySize]{};
    alignas(16) unsigned char block_copy[kSharedBlockCopySize]{};
    alignas(16) unsigned char node30_copy[0x100]{};
    alignas(16) unsigned char nodea8_copy[0x100]{};
    const bool queue_ok = safe_copy(queue_copy, queue, sizeof(queue_copy));
    const uint64_t block_ptr = queue_ok ? read_u64(queue_copy, 0x48) : 0;
    const bool block_ok = block_ptr != 0 && safe_copy(block_copy, reinterpret_cast<void*>(block_ptr), sizeof(block_copy));

    const uint16_t block_cursor = block_ok ? read_u16(block_copy, 0x12) : 0;
    const uint16_t block_count = block_ok ? read_u16(block_copy, 0x14) : 0;
    uint16_t place_entry_offset = 0;
    uint16_t place_node_offset = 0;
    const bool place_node_found =
        block_ok &&
        find_place_prefab_node_offset(block_copy, sizeof(block_copy), &place_node_offset, &place_entry_offset);
    const uintptr_t node30_ptr = place_node_found ? static_cast<uintptr_t>(block_ptr) + place_node_offset : 0;
    const uintptr_t nodea8_ptr =
        block_ptr != 0 && block_cursor >= 0xA8
            ? static_cast<uintptr_t>(block_ptr) + static_cast<uintptr_t>(block_cursor) - 0xA8
            : 0;
    const bool node30_ok = node30_ptr != 0 && safe_copy(node30_copy, reinterpret_cast<void*>(node30_ptr), sizeof(node30_copy));
    const bool nodea8_ok = nodea8_ptr != 0 && safe_copy(nodea8_copy, reinterpret_cast<void*>(nodea8_ptr), sizeof(nodea8_copy));

    const long hit = g_shared_hits.fetch_add(1) + 1;
    log_line(
        "shared_submit_hit=%ld caller_va=0x%llX owner=%p queue=%p args=%llu,%llu replay=%d queue_ok=%d q40=%p q48=%p q58=%u q5a=%u q5c=%d q60=%d block_ok=%d block_cursor=%u block_count=%u place_found=%d place_entry=0x%X place_node=%p place_desc=%p place_prefab=%p place_pos=%d,%d,%d place_orient=%u nodea8=%p nodea8_desc=%p nodea8_q18=%p",
        hit,
        static_cast<unsigned long long>(caller_va),
        owner,
        queue,
        static_cast<unsigned long long>(arg2),
        static_cast<unsigned long long>(arg3),
        g_shared_replay_in_progress ? 1 : 0,
        queue_ok ? 1 : 0,
        queue_ok ? reinterpret_cast<void*>(read_u64(queue_copy, 0x40)) : nullptr,
        queue_ok ? reinterpret_cast<void*>(read_u64(queue_copy, 0x48)) : nullptr,
        queue_ok ? static_cast<unsigned>(queue_copy[0x58]) : 0xffu,
        queue_ok ? static_cast<unsigned>(queue_copy[0x5A]) : 0xffu,
        queue_ok ? read_i32(queue_copy, 0x5C) : 0,
        queue_ok ? read_i32(queue_copy, 0x60) : 0,
        block_ok ? 1 : 0,
        static_cast<unsigned>(block_cursor),
        static_cast<unsigned>(block_count),
        place_node_found ? 1 : 0,
        static_cast<unsigned>(place_entry_offset),
        reinterpret_cast<void*>(node30_ptr),
        node30_ok ? reinterpret_cast<void*>(read_u64(node30_copy, 0x00)) : nullptr,
        node30_ok ? reinterpret_cast<void*>(read_u64(node30_copy, 0x18)) : nullptr,
        node30_ok ? read_i32(node30_copy, 0x20) : 0,
        node30_ok ? read_i32(node30_copy, 0x24) : 0,
        node30_ok ? read_i32(node30_copy, 0x28) : 0,
        node30_ok ? static_cast<unsigned>(node30_copy[0x2C]) : 0xffu,
        reinterpret_cast<void*>(nodea8_ptr),
        nodea8_ok ? reinterpret_cast<void*>(read_u64(nodea8_copy, 0x00)) : nullptr,
        nodea8_ok ? reinterpret_cast<void*>(read_u64(nodea8_copy, 0x18)) : nullptr);

    if (block_ok) {
        log_shared_nodes("shared", hit, block_copy, static_cast<uintptr_t>(block_ptr));
    }

    if (!g_shared_replay_in_progress && queue_ok && block_ok && place_node_found) {
        capture_latest_shared(
            owner,
            queue,
            reinterpret_cast<void*>(block_ptr),
            arg2,
            arg3,
            block_cursor,
            block_count,
            place_node_offset,
            queue_copy,
            block_copy);
        log_line(
            "captured_shared owner=%p queue=%p block=%p target_registry=%p target_id=%d place_node=0x%X source_offset=%d,%d,%d count=%u",
            owner,
            queue,
            reinterpret_cast<void*>(block_ptr),
            g_latest_target_registry,
            g_latest_target_id,
            static_cast<unsigned>(place_node_offset),
            read_i32(block_copy, place_node_offset + 0x20),
            read_i32(block_copy, place_node_offset + 0x24),
            read_i32(block_copy, place_node_offset + 0x28),
            static_cast<unsigned>(block_count));
    }

    return g_original_shared(owner, queue, arg2, arg3);
}

void* __fastcall hook_additive_load(void* manager, void* out_result, void* bundle_or_archive, void* params, void* context) {
    if (!g_original) {
        return nullptr;
    }

    alignas(16) unsigned char params_copy[kParamsSize]{};
    const bool params_ok = safe_copy(params_copy, params, sizeof(params_copy));
    const uint8_t bundle_state = safe_read_u8(bundle_or_archive, 0x33, 0xff);
    const int32_t x = params_ok ? read_i32(params_copy, 0x08) : 0;
    const int32_t y = params_ok ? read_i32(params_copy, 0x0C) : 0;
    const int32_t z = params_ok ? read_i32(params_copy, 0x10) : 0;
    const uint8_t orientation = params_ok ? params_copy[0x14] : 0xff;
    const int32_t brick_grid = params_ok ? read_i32(params_copy, 0x20) : 0;
    const long hit = g_hits.fetch_add(1) + 1;

    const bool replaying = g_replay_in_progress;
    if (replaying) {
        ++g_replay_additive_hits;
    }

    log_line(
        "additive_hit=%ld manager=%p out=%p bundle=%p context=%p params=%p ok=%d replay=%d state=%u global=%p preview=%p offset=%d,%d,%d orient=%u brick_grid=%d flags=%u,%u,%u",
        hit,
        manager,
        out_result,
        bundle_or_archive,
        context,
        params,
        params_ok ? 1 : 0,
        replaying ? 1 : 0,
        static_cast<unsigned>(bundle_state),
        params_ok ? reinterpret_cast<void*>(read_u64(params_copy, 0x00)) : nullptr,
        params_ok ? reinterpret_cast<void*>(read_u64(params_copy, 0x18)) : nullptr,
        x,
        y,
        z,
        static_cast<unsigned>(orientation),
        brick_grid,
        params_ok ? static_cast<unsigned>(params_copy[0x24]) : 0xffu,
        params_ok ? static_cast<unsigned>(params_copy[0x25]) : 0xffu,
        params_ok ? static_cast<unsigned>(params_copy[0x26]) : 0xffu);

    const uint64_t global_target = params_ok ? read_u64(params_copy, 0x00) : 0;
    const uint64_t preview_part = params_ok ? read_u64(params_copy, 0x18) : 0;
    const bool is_committed_global_load = params_ok && global_target != 0 && preview_part == 0;
    if (is_committed_global_load && !replaying) {
        capture_latest_global(manager, bundle_or_archive, params, context, params_copy);
        log_line("captured_global_additive manager=%p bundle=%p context=%p offset=%d,%d,%d", manager, bundle_or_archive, context, x, y, z);
    } else if (is_committed_global_load && replaying) {
        log_line("ignored_replay_seed manager=%p bundle=%p context=%p offset=%d,%d,%d", manager, bundle_or_archive, context, x, y, z);
    }

    void* result = g_original(manager, out_result, bundle_or_archive, params, context);

    const Control control = read_control();
    const long duplicate_count = g_duplicates.load();
    if (replaying || !is_committed_global_load || !control.duplicate || duplicate_count >= control.limit) {
        return result;
    }

    const long next_duplicate = g_duplicates.fetch_add(1) + 1;
    if (next_duplicate > control.limit) {
        return result;
    }

    alignas(16) unsigned char duplicate_params[kParamsSize]{};
    alignas(16) unsigned char duplicate_result[0x80]{};
    std::memcpy(duplicate_params, params_copy, sizeof(duplicate_params));
    write_i32(duplicate_params, 0x0C, y + control.y_offset);

    log_line(
        "duplicate_additive=%ld/%ld source_offset=%d,%d,%d duplicate_offset=%d,%d,%d y_offset=%d",
        next_duplicate,
        control.limit,
        x,
        y,
        z,
        x,
        y + control.y_offset,
        z,
        control.y_offset);

    g_original(manager, duplicate_result, bundle_or_archive, duplicate_params, context);
    return result;
}

DWORD WINAPI install_thread(void*) {
    HMODULE module = nullptr;
    for (int i = 0; i < 100 && !module; ++i) {
        module = GetModuleHandleW(L"BrickadiaServer-Win64-Shipping.exe");
        if (!module) {
            Sleep(100);
        }
    }

    if (!module) {
        log_line("install_failed missing BrickadiaServer module");
        return 0;
    }
    g_module_base = reinterpret_cast<uintptr_t>(module);

    void* additive_trampoline = nullptr;
    bool additive_chained = false;
    if (!install_absolute_hook(
            module,
            "additive",
            kAdditiveLoadRva,
            kExpectedPrologue,
            kPatchLen,
            reinterpret_cast<void*>(&hook_additive_load),
            &additive_trampoline,
            &additive_chained)) {
        return 0;
    }

    g_trampoline = additive_trampoline;
    g_original = reinterpret_cast<AdditiveLoadFn>(additive_trampoline);
    g_outer_additive = reinterpret_cast<OuterAdditiveLoadFn>(reinterpret_cast<uintptr_t>(module) + kOuterAdditiveLoadRva);

    g_installed = true;
    log_line(
        "configured_additive outer=%p chain=%d duplicate_control=%ls",
        g_outer_additive,
        additive_chained ? 1 : 0,
        kControlPath);

    void* action_trampoline = nullptr;
    bool action_chained = false;
    if (!install_absolute_hook(
            module,
            "action",
            kActionSubmitterRva,
            kExpectedActionPrologue,
            kActionPatchLen,
            reinterpret_cast<void*>(&hook_action_submitter),
            &action_trampoline,
            &action_chained)) {
        log_line("install_warning action_unavailable commands_will_fallback_to_additive");
    } else {
        g_action_trampoline = action_trampoline;
        g_original_action = reinterpret_cast<ActionSubmitterFn>(action_trampoline);
        g_action_installed = true;
        log_line("configured_action submitter=%p chain=%d", g_original_action, action_chained ? 1 : 0);
    }

    void* shared_trampoline = nullptr;
    bool shared_chained = false;
    if (!install_absolute_hook(
            module,
            "shared_submit",
            kSharedSubmitRva,
            kExpectedSharedPrologue,
            kSharedPatchLen,
            reinterpret_cast<void*>(&hook_shared_submit),
            &shared_trampoline,
            &shared_chained)) {
        log_line("install_warning shared_submit_unavailable caller_probe_disabled");
    } else {
        g_shared_trampoline = shared_trampoline;
        g_original_shared = reinterpret_cast<SharedSubmitFn>(shared_trampoline);
        g_shared_installed = true;
        log_line("configured_shared_submit submitter=%p chain=%d", g_original_shared, shared_chained ? 1 : 0);
    }

    void* target_allocator_trampoline = nullptr;
    bool target_allocator_chained = false;
    if (!install_absolute_hook(
            module,
            "target_allocator",
            kTargetAllocatorRva,
            kExpectedTargetAllocatorPrologue,
            kTargetAllocatorPatchLen,
            reinterpret_cast<void*>(&hook_target_allocator),
            &target_allocator_trampoline,
            &target_allocator_chained)) {
        log_line("install_warning target_allocator_unavailable shared_replay_will_refuse_stale_target_ids");
    } else {
        g_target_allocator_trampoline = target_allocator_trampoline;
        g_original_target_allocator = reinterpret_cast<TargetAllocatorFn>(target_allocator_trampoline);
        g_target_allocator_installed = true;
        log_line(
            "configured_target_allocator allocator=%p chain=%d",
            g_original_target_allocator,
            target_allocator_chained ? 1 : 0);
    }

    register_engine_tick_callback();
    return 0;
}

} // namespace

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(module);
        HANDLE thread = CreateThread(nullptr, 0, &install_thread, nullptr, 0, nullptr);
        if (thread) {
            CloseHandle(thread);
        }
    }
    return TRUE;
}
