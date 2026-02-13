#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [--tool amp|claude] [max_iterations]

set -e

# Parse arguments
TOOL="amp"  # Default to amp for backwards compatibility
MAX_ITERATIONS=10

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    *)
      # Assume it's max_iterations if it's a number
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

# Validate tool choice
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp' or 'claude'."
  exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
LOG_DIR="$SCRIPT_DIR/ralph-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/ralph-$(date +%Y-%m-%d-%H%M%S).log"

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    
    # Reset progress file for new run
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Initialize log file
echo "# Ralph Output Log" > "$LOG_FILE"
echo "Started: $(date)" >> "$LOG_FILE"
echo "Tool: $TOOL - Max iterations: $MAX_ITERATIONS" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

echo "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS"
echo "Output log: $LOG_FILE"
echo "Monitor with: tail -f $LOG_FILE"

# Initialize cumulative token counters (for claude)
CUMUL_INPUT=0
CUMUL_OUTPUT=0
CUMUL_CACHE_READ=0
CUMUL_CACHE_CREATE=0
CUMUL_TURNS=0

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"
  echo "==============================================================="

  # Capture iteration start time
  ITER_START_EPOCH=$(date +%s)
  ITER_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')

  # Log iteration header
  echo "" >> "$LOG_FILE"
  echo "===============================================================" >> "$LOG_FILE"
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)" >> "$LOG_FILE"
  echo "  Started: $ITER_START_TIME" >> "$LOG_FILE"
  echo "===============================================================" >> "$LOG_FILE"

  # Run the selected tool with the ralph prompt
  if [[ "$TOOL" == "amp" ]]; then
    OUTPUT=$(cat "$SCRIPT_DIR/prompt.md" | amp --dangerously-allow-all 2>&1 | tee -a "$LOG_FILE") || true
  else
    # Claude Code: use --dangerously-skip-permissions with JSON output for usage stats
    JSON_OUTPUT=$(claude --dangerously-skip-permissions --print --output-format json < "$SCRIPT_DIR/CLAUDE.md" 2>&1) || true

    # Extract the text result for logging and completion check
    OUTPUT=$(echo "$JSON_OUTPUT" | jq -r '.result // empty' 2>/dev/null) || OUTPUT="$JSON_OUTPUT"

    # Log the text result
    echo "$OUTPUT" >> "$LOG_FILE"

    # Extract usage stats from JSON (use 0 as fallback for arithmetic)
    USAGE_INPUT=$(echo "$JSON_OUTPUT" | jq -r '.usage.input_tokens // 0' 2>/dev/null) || USAGE_INPUT=0
    USAGE_OUTPUT=$(echo "$JSON_OUTPUT" | jq -r '.usage.output_tokens // 0' 2>/dev/null) || USAGE_OUTPUT=0
    USAGE_CACHE_READ=$(echo "$JSON_OUTPUT" | jq -r '.usage.cache_read_input_tokens // 0' 2>/dev/null) || USAGE_CACHE_READ=0
    USAGE_CACHE_CREATE=$(echo "$JSON_OUTPUT" | jq -r '.usage.cache_creation_input_tokens // 0' 2>/dev/null) || USAGE_CACHE_CREATE=0
    USAGE_NUM_TURNS=$(echo "$JSON_OUTPUT" | jq -r '.num_turns // 0' 2>/dev/null) || USAGE_NUM_TURNS=0

    # Update cumulative totals
    CUMUL_INPUT=$((CUMUL_INPUT + USAGE_INPUT))
    CUMUL_OUTPUT=$((CUMUL_OUTPUT + USAGE_OUTPUT))
    CUMUL_CACHE_READ=$((CUMUL_CACHE_READ + USAGE_CACHE_READ))
    CUMUL_CACHE_CREATE=$((CUMUL_CACHE_CREATE + USAGE_CACHE_CREATE))
    CUMUL_TURNS=$((CUMUL_TURNS + USAGE_NUM_TURNS))

    # Add token usage to the completed story in prd.json
    # Find story with completedAt but no tokenUsage and add the metrics
    if [ -f "$PRD_FILE" ]; then
      UPDATED_PRD=$(jq --argjson input "$USAGE_INPUT" \
                       --argjson output "$USAGE_OUTPUT" \
                       --argjson cache_read "$USAGE_CACHE_READ" \
                       --argjson cache_create "$USAGE_CACHE_CREATE" \
                       --argjson turns "$USAGE_NUM_TURNS" '
        .features |= map(
          .userStories |= map(
            if .completedAt != null and .tokenUsage == null then
              .tokenUsage = {
                input: $input,
                output: $output,
                cacheRead: $cache_read,
                cacheCreate: $cache_create,
                turns: $turns
              }
            else
              .
            end
          )
        )
      ' "$PRD_FILE" 2>/dev/null) && echo "$UPDATED_PRD" > "$PRD_FILE"
    fi
  fi

  # Capture iteration end time and calculate duration
  ITER_END_EPOCH=$(date +%s)
  ITER_END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
  ITER_DURATION=$((ITER_END_EPOCH - ITER_START_EPOCH))
  ITER_MINUTES=$((ITER_DURATION / 60))
  ITER_SECONDS=$((ITER_DURATION % 60))

  # Log iteration timing summary
  echo "" >> "$LOG_FILE"
  echo "╔═══════════════════════════════════════════════════════════════╗" >> "$LOG_FILE"
  echo "║  Iteration $i Summary                                          " >> "$LOG_FILE"
  echo "╠═══════════════════════════════════════════════════════════════╣" >> "$LOG_FILE"
  echo "║  TIMING                                                        " >> "$LOG_FILE"
  echo "║    Started:  $ITER_START_TIME                                  " >> "$LOG_FILE"
  echo "║    Ended:    $ITER_END_TIME                                    " >> "$LOG_FILE"
  echo "║    Duration: ${ITER_MINUTES}m ${ITER_SECONDS}s (${ITER_DURATION}s total)" >> "$LOG_FILE"
  if [[ "$TOOL" == "claude" ]]; then
    echo "╠═══════════════════════════════════════════════════════════════╣" >> "$LOG_FILE"
    echo "║  TOKENS (this iteration)                                      " >> "$LOG_FILE"
    echo "║    Input:          ${USAGE_INPUT}                             " >> "$LOG_FILE"
    echo "║    Output:         ${USAGE_OUTPUT}                            " >> "$LOG_FILE"
    echo "║    Cache read:     ${USAGE_CACHE_READ}                        " >> "$LOG_FILE"
    echo "║    Cache creation: ${USAGE_CACHE_CREATE}                      " >> "$LOG_FILE"
    echo "║    Num turns:      ${USAGE_NUM_TURNS}                         " >> "$LOG_FILE"
    echo "╠═══════════════════════════════════════════════════════════════╣" >> "$LOG_FILE"
    echo "║  TOKENS (cumulative this run)                                 " >> "$LOG_FILE"
    echo "║    Input:          ${CUMUL_INPUT}                             " >> "$LOG_FILE"
    echo "║    Output:         ${CUMUL_OUTPUT}                            " >> "$LOG_FILE"
    echo "║    Cache read:     ${CUMUL_CACHE_READ}                        " >> "$LOG_FILE"
    echo "║    Cache creation: ${CUMUL_CACHE_CREATE}                      " >> "$LOG_FILE"
    echo "║    Num turns:      ${CUMUL_TURNS}                             " >> "$LOG_FILE"
  fi
  echo "╚═══════════════════════════════════════════════════════════════╝" >> "$LOG_FILE"

  # Check for completion signal
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks!"
    if [[ "$TOOL" == "claude" ]]; then
      echo "Completed at iteration $i of $MAX_ITERATIONS (took ${ITER_MINUTES}m ${ITER_SECONDS}s, ${USAGE_NUM_TURNS} turns)"
      echo ""
      echo "Total tokens used this run:"
      echo "  Input:          ${CUMUL_INPUT}"
      echo "  Output:         ${CUMUL_OUTPUT}"
      echo "  Cache read:     ${CUMUL_CACHE_READ}"
      echo "  Cache creation: ${CUMUL_CACHE_CREATE}"
      echo "  Total turns:    ${CUMUL_TURNS}"
      # Log final summary
      echo "" >> "$LOG_FILE"
      echo "╔═══════════════════════════════════════════════════════════════╗" >> "$LOG_FILE"
      echo "║  RALPH RUN COMPLETE - FINAL SUMMARY                           " >> "$LOG_FILE"
      echo "╠═══════════════════════════════════════════════════════════════╣" >> "$LOG_FILE"
      echo "║  Iterations: $i                                               " >> "$LOG_FILE"
      echo "║  Total tokens:                                                " >> "$LOG_FILE"
      echo "║    Input:          ${CUMUL_INPUT}                             " >> "$LOG_FILE"
      echo "║    Output:         ${CUMUL_OUTPUT}                            " >> "$LOG_FILE"
      echo "║    Cache read:     ${CUMUL_CACHE_READ}                        " >> "$LOG_FILE"
      echo "║    Cache creation: ${CUMUL_CACHE_CREATE}                      " >> "$LOG_FILE"
      echo "║    Total turns:    ${CUMUL_TURNS}                             " >> "$LOG_FILE"
      echo "╚═══════════════════════════════════════════════════════════════╝" >> "$LOG_FILE"
    else
      echo "Completed at iteration $i of $MAX_ITERATIONS (took ${ITER_MINUTES}m ${ITER_SECONDS}s)"
    fi
    exit 0
  fi

  if [[ "$TOOL" == "claude" ]]; then
    echo "Iteration $i complete (took ${ITER_MINUTES}m ${ITER_SECONDS}s, ${USAGE_NUM_TURNS} turns). Continuing..."
  else
    echo "Iteration $i complete (took ${ITER_MINUTES}m ${ITER_SECONDS}s). Continuing..."
  fi
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."

if [[ "$TOOL" == "claude" ]]; then
  echo ""
  echo "Total tokens used this run:"
  echo "  Input:          ${CUMUL_INPUT}"
  echo "  Output:         ${CUMUL_OUTPUT}"
  echo "  Cache read:     ${CUMUL_CACHE_READ}"
  echo "  Cache creation: ${CUMUL_CACHE_CREATE}"
  echo "  Total turns:    ${CUMUL_TURNS}"
  # Log final summary
  echo "" >> "$LOG_FILE"
  echo "╔═══════════════════════════════════════════════════════════════╗" >> "$LOG_FILE"
  echo "║  RALPH RUN ENDED (MAX ITERATIONS) - FINAL SUMMARY             " >> "$LOG_FILE"
  echo "╠═══════════════════════════════════════════════════════════════╣" >> "$LOG_FILE"
  echo "║  Iterations: $MAX_ITERATIONS                                  " >> "$LOG_FILE"
  echo "║  Total tokens:                                                " >> "$LOG_FILE"
  echo "║    Input:          ${CUMUL_INPUT}                             " >> "$LOG_FILE"
  echo "║    Output:         ${CUMUL_OUTPUT}                            " >> "$LOG_FILE"
  echo "║    Cache read:     ${CUMUL_CACHE_READ}                        " >> "$LOG_FILE"
  echo "║    Cache creation: ${CUMUL_CACHE_CREATE}                      " >> "$LOG_FILE"
  echo "║    Total turns:    ${CUMUL_TURNS}                             " >> "$LOG_FILE"
  echo "╚═══════════════════════════════════════════════════════════════╝" >> "$LOG_FILE"
fi

exit 1
