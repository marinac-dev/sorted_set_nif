#!/bin/bash
set -e

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Lock vs Try-Lock Benchmark Comparison${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

NATIVE_DIR="native/sorted_set_nif/src"
RESULTS_DIR="bench/results/lock_comparison"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Verify required files exist
if [ ! -f "$NATIVE_DIR/lib_lock.rs" ]; then
    echo -e "${RED}❌ Error: lib_lock.rs not found${NC}"
    exit 1
fi

if [ ! -f "$NATIVE_DIR/lib_try_lock.rs" ]; then
    echo -e "${RED}❌ Error: lib_try_lock.rs not found${NC}"
    exit 1
fi

echo -e "${CYAN}📦 Step 1: Benchmark with lock() implementation${NC}"
echo -e "${CYAN}--------------------------------------------${NC}"
echo -e "${YELLOW}Using standard .lock() implementation...${NC}"

# Backup current lib.rs
cp "$NATIVE_DIR/lib.rs" "$NATIVE_DIR/lib_current_backup.rs"
echo -e "${GREEN}✓${NC} Backed up current lib.rs"

# Use lock version
cp "$NATIVE_DIR/lib_lock.rs" "$NATIVE_DIR/lib.rs"
echo -e "${GREEN}✓${NC} Switched to lib_lock.rs"

echo ""
echo -e "${YELLOW}Recompiling NIF with lock()...${NC}"
if ! mix deps.compile rustler --force 2>&1 | tee "$RESULTS_DIR/lock_compile.log"; then
    echo -e "${RED}❌ Compilation failed for lock version!${NC}"
    echo -e "${RED}See $RESULTS_DIR/lock_compile.log for details${NC}"
    # Restore original
    cp "$NATIVE_DIR/lib_current_backup.rs" "$NATIVE_DIR/lib.rs"
    rm "$NATIVE_DIR/lib_current_backup.rs"
    exit 1
fi

if ! mix compile --force 2>&1 | tee -a "$RESULTS_DIR/lock_compile.log"; then
    echo -e "${RED}❌ Elixir compilation failed for lock version!${NC}"
    echo -e "${RED}See $RESULTS_DIR/lock_compile.log for details${NC}"
    # Restore original
    cp "$NATIVE_DIR/lib_current_backup.rs" "$NATIVE_DIR/lib.rs"
    rm "$NATIVE_DIR/lib_current_backup.rs"
    exit 1
fi

echo -e "${GREEN}✓ Compilation successful${NC}"

echo ""
echo -e "${YELLOW}Running benchmark with lock()...${NC}"
if ! mix run bench/leaderboard_lock_comparison.exs 2>&1 | tee "$RESULTS_DIR/lock_version_output.txt"; then
    echo -e "${RED}❌ Benchmark failed for lock version!${NC}"
    # Restore original
    cp "$NATIVE_DIR/lib_current_backup.rs" "$NATIVE_DIR/lib.rs"
    rm "$NATIVE_DIR/lib_current_backup.rs"
    exit 1
fi

echo -e "${GREEN}✓ Benchmark complete${NC}"

echo ""
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "${CYAN}📦 Step 2: Benchmark with try_lock() implementation${NC}"
echo -e "${CYAN}--------------------------------------------${NC}"
echo -e "${YELLOW}Using .try_lock() with error handling implementation...${NC}"

# Use try_lock version
cp "$NATIVE_DIR/lib_try_lock.rs" "$NATIVE_DIR/lib.rs"
echo -e "${GREEN}✓${NC} Switched to lib_try_lock.rs"

echo ""
echo -e "${YELLOW}Recompiling NIF with try_lock()...${NC}"
if ! mix deps.compile rustler --force 2>&1 | tee "$RESULTS_DIR/try_lock_compile.log"; then
    echo -e "${RED}❌ Compilation failed for try_lock version!${NC}"
    echo -e "${RED}See $RESULTS_DIR/try_lock_compile.log for details${NC}"
    # Restore original
    cp "$NATIVE_DIR/lib_current_backup.rs" "$NATIVE_DIR/lib.rs"
    rm "$NATIVE_DIR/lib_current_backup.rs"
    exit 1
fi

if ! mix compile --force 2>&1 | tee -a "$RESULTS_DIR/try_lock_compile.log"; then
    echo -e "${RED}❌ Elixir compilation failed for try_lock version!${NC}"
    echo -e "${RED}See $RESULTS_DIR/try_lock_compile.log for details${NC}"
    # Restore original
    cp "$NATIVE_DIR/lib_current_backup.rs" "$NATIVE_DIR/lib.rs"
    rm "$NATIVE_DIR/lib_current_backup.rs"
    exit 1
fi

echo -e "${GREEN}✓ Compilation successful${NC}"

echo ""
echo -e "${YELLOW}Running benchmark with try_lock()...${NC}"
if ! mix run bench/leaderboard_lock_comparison.exs 2>&1 | tee "$RESULTS_DIR/try_lock_version_output.txt"; then
    echo -e "${RED}❌ Benchmark failed for try_lock version!${NC}"
    # Restore original
    cp "$NATIVE_DIR/lib_current_backup.rs" "$NATIVE_DIR/lib.rs"
    rm "$NATIVE_DIR/lib_current_backup.rs"
    exit 1
fi

echo -e "${GREEN}✓ Benchmark complete${NC}"

echo ""
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "${CYAN}📦 Step 3: Restoring original implementation${NC}"
echo -e "${CYAN}--------------------------------------------${NC}"

# Restore original
cp "$NATIVE_DIR/lib_current_backup.rs" "$NATIVE_DIR/lib.rs"
rm "$NATIVE_DIR/lib_current_backup.rs"
echo -e "${GREEN}✓${NC} Restored original lib.rs"

echo ""
echo -e "${YELLOW}Recompiling with original implementation...${NC}"
if ! mix deps.compile rustler --force 2>&1 | tee "$RESULTS_DIR/restore_compile.log"; then
    echo -e "${RED}⚠️  Warning: Restoration compilation failed!${NC}"
    echo -e "${RED}See $RESULTS_DIR/restore_compile.log for details${NC}"
    echo -e "${YELLOW}You may need to manually restore your lib.rs${NC}"
else
    if ! mix compile --force 2>&1 | tee -a "$RESULTS_DIR/restore_compile.log"; then
        echo -e "${RED}⚠️  Warning: Elixir restoration compilation failed!${NC}"
        echo -e "${RED}See $RESULTS_DIR/restore_compile.log for details${NC}"
    else
        echo -e "${GREEN}✓ Restoration successful${NC}"
    fi
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}✅ BENCHMARK COMPLETE!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${CYAN}Results saved to:${NC}"
echo -e "  ${YELLOW}- $RESULTS_DIR/lock_version_output.txt${NC}"
echo -e "  ${YELLOW}- $RESULTS_DIR/try_lock_version_output.txt${NC}"
echo -e "  ${YELLOW}- $RESULTS_DIR/lock_compile.log${NC}"
echo -e "  ${YELLOW}- $RESULTS_DIR/try_lock_compile.log${NC}"
echo ""
echo -e "${CYAN}Compare the output files to see performance differences!${NC}"
echo ""
echo -e "${YELLOW}Quick comparison:${NC}"
echo -e "  Lock version stats:"
grep -E "(ips|average|memory)" "$RESULTS_DIR/lock_version_output.txt" | head -20 || true
echo ""
echo -e "  Try-lock version stats:"
grep -E "(ips|average|memory)" "$RESULTS_DIR/try_lock_version_output.txt" | head -20 || true
echo ""

