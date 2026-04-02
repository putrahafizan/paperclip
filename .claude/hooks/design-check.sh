#!/usr/bin/env bash
# design-check.sh — PostToolUse hook for Write|Edit
# Checks CSS/JSX/TSX files for forbidden design patterns.
# Output to stdout (Claude reads). Always exit 0.

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Only check design-relevant files
if ! echo "$FILE_PATH" | grep -qE '\.(css|scss|jsx|tsx)$'; then
  exit 0
fi

WARNINGS=""
DESIGN_DIR="$PROJECT_ROOT/docs/design-direction.md"

# Default forbidden fonts: Inter, Roboto, Arial, Poppins, system-ui
# These are generic/overused fonts that indicate AI slop
FORBIDDEN_FONTS="Inter|Roboto|Arial|Poppins|system-ui"

# Load custom forbidden fonts from design-direction.md if exists
if [ -f "$DESIGN_DIR" ]; then
  CUSTOM_FONTS=$(grep -i 'forbidden.*font\|font.*forbidden\|DILARANG.*font' "$DESIGN_DIR" | grep -oE "'[^']+'" | tr -d "'" | paste -sd '|' 2>/dev/null)
  if [ -n "$CUSTOM_FONTS" ]; then
    FORBIDDEN_FONTS="$CUSTOM_FONTS"
  fi
fi

# Check forbidden fonts
if [ -f "$FILE_PATH" ]; then
  FONT_MATCHES=$(grep -inE "font-family.*($FORBIDDEN_FONTS)" "$FILE_PATH" 2>/dev/null || true)
  if [ -n "$FONT_MATCHES" ]; then
    WARNINGS="${WARNINGS}⚠️ DESIGN: Forbidden font detected in $FILE_PATH:\n$FONT_MATCHES\n"
  fi

  # Check forbidden patterns
  # Purple gradient
  if grep -qiE 'purple.*gradient|gradient.*purple|#[89a-f][0-9a-f].*#[89a-f]' "$FILE_PATH" 2>/dev/null; then
    WARNINGS="${WARNINGS}⚠️ DESIGN: Purple gradient pattern detected in $FILE_PATH\n"
  fi

  # Heavy box-shadow blur
  if grep -qE 'box-shadow.*\b[2-9][0-9]px' "$FILE_PATH" 2>/dev/null; then
    WARNINGS="${WARNINGS}⚠️ DESIGN: Heavy box-shadow blur (>20px) detected in $FILE_PATH\n"
  fi

  # Excessive border-radius
  if grep -qE 'border-radius:\s*[2-9][0-9]px|border-radius:\s*[1-9][0-9]{2,}px' "$FILE_PATH" 2>/dev/null; then
    WARNINGS="${WARNINGS}⚠️ DESIGN: Excessive border-radius (>16px) detected in $FILE_PATH\n"
  fi

  # --- Enhanced anti-slop patterns (from ui-ux-pro-max) ---

  # Pink-to-purple gradient (broader than just purple)
  if grep -qiE 'from-pink.*to-purple|from-purple.*to-pink|#[efd][0-9a-f].*#[89a][0-9a-f].*gradient|pink.*purple.*gradient|fuchsia.*violet' "$FILE_PATH" 2>/dev/null; then
    WARNINGS="${WARNINGS}⚠️ DESIGN: Pink-to-purple gradient detected (AI slop pattern) in $FILE_PATH\n"
  fi

  # Overuse of rounded-full (pill shapes everywhere)
  PILL_COUNT=$(grep -coE 'rounded-full|border-radius:\s*9999|border-radius:\s*50%' "$FILE_PATH" 2>/dev/null || echo "0")
  if [ "$PILL_COUNT" -gt 5 ]; then
    WARNINGS="${WARNINGS}⚠️ DESIGN: Excessive rounded-full usage (${PILL_COUNT} instances) in $FILE_PATH — consider mixed border-radius\n"
  fi

  # Generic hero section pattern (heading + subtitle + single CTA = AI template)
  if grep -qE 'className.*hero' "$FILE_PATH" 2>/dev/null; then
    # Check if it follows the generic pattern: h1 + p + button with no unique elements
    HERO_ELEMENTS=$(grep -cE '<h[12]|<p|<button|<Button' "$FILE_PATH" 2>/dev/null || echo "0")
    UNIQUE_ELEMENTS=$(grep -cE '<img|<video|<svg|<canvas|<lottie|animation|motion' "$FILE_PATH" 2>/dev/null || echo "0")
    if [ "$HERO_ELEMENTS" -gt 2 ] && [ "$UNIQUE_ELEMENTS" -eq 0 ]; then
      WARNINGS="${WARNINGS}⚠️ DESIGN: Generic hero section pattern (heading+text+CTA, no unique elements) in $FILE_PATH\n"
    fi
  fi

  # Stock placeholder image filenames
  if grep -qiE 'placeholder\.(png|jpg|svg)|unsplash\.com|picsum\.photos|via\.placeholder|lorem-pixel|stock-photo' "$FILE_PATH" 2>/dev/null; then
    WARNINGS="${WARNINGS}⚠️ DESIGN: Placeholder/stock image reference detected in $FILE_PATH — replace with real assets\n"
  fi
fi

if [ -n "$WARNINGS" ]; then
  echo -e "$WARNINGS"
fi

exit 0
