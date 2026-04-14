#!/bin/bash
set -euo pipefail

# Build all JS dependencies from npm using esbuild.
# Each library is bundled as a self-contained IIFE that sets window.* globals.
# Output goes to Shared/Resources/.
#
# Usage: ./scripts/build-js-deps.sh
#
# To update versions, edit the npm install line below.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/Shared/Resources"
WORK_DIR=$(mktemp -d)

echo "Building JS dependencies..."
echo "  Work dir: $WORK_DIR"
echo "  Output:   $OUTPUT_DIR"
echo ""

cd "$WORK_DIR"
npm init -y --silent > /dev/null

# ============================================================
# Pin versions here for reproducible builds
# ============================================================
npm install --silent \
  highlight.js@11.11.1 \
  temml@0.13.2 \
  mermaid@11.14.0 \
  2>&1 | tail -1

# ============================================================
# 1. highlight.js (common languages → window.hljs)
# ============================================================
cat > entry-hljs.js << 'EOF'
import hljs from 'highlight.js/lib/common';
window.hljs = hljs;
EOF

npx esbuild entry-hljs.js \
  --bundle --minify --format=iife \
  --outfile="$OUTPUT_DIR/highlight.min.js" \
  2>&1 | grep -v "^$"

echo "  highlight.js: $(du -h "$OUTPUT_DIR/highlight.min.js" | awk '{print $1}') ($(node -e "
  global.window = {};
  require('$OUTPUT_DIR/highlight.min.js');
  console.log(window.hljs.listLanguages().length + ' languages');
"))"

# ============================================================
# 2. Temml (→ window.temml)
#    Outputs MathML — macOS WebKit renders natively with STIX Two system fonts.
#    No custom fonts needed (unlike KaTeX).
# ============================================================
cat > entry-temml.js << 'EOF'
import temml from 'temml';
window.temml = temml;
EOF

npx esbuild entry-temml.js \
  --bundle --minify --format=iife \
  --outfile="$OUTPUT_DIR/temml.min.js" \
  2>&1 | grep -v "^$"

echo "  temml.js:      $(du -h "$OUTPUT_DIR/temml.min.js" | awk '{print $1}')"

# ============================================================
# 3. Temml CSS (Temml-Local uses system fonts — ideal for macOS)
# ============================================================
TEMML_CSS="node_modules/temml/dist/Temml-Local.css"
cp "$TEMML_CSS" "$OUTPUT_DIR/temml.min.css"
# Temml.woff2 provides \mathscr (script capitals) and prime symbols
cp "node_modules/temml/dist/Temml.woff2" "$OUTPUT_DIR/Temml.woff2"
echo "  temml.css:     $(du -h "$OUTPUT_DIR/temml.min.css" | awk '{print $1}') (system fonts + Temml.woff2 for \\mathscr)"

# ============================================================
# 4. Mermaid (→ window.mermaid)
# ============================================================
cat > entry-mermaid.js << 'EOF'
import mermaid from 'mermaid';
window.mermaid = mermaid;
EOF

npx esbuild entry-mermaid.js \
  --bundle --minify --format=iife \
  --outfile="$OUTPUT_DIR/mermaid.min.js" \
  2>&1 | grep -v "^$"

echo "  mermaid.js:    $(du -h "$OUTPUT_DIR/mermaid.min.js" | awk '{print $1}')"

# ============================================================
# 5. highlight.js GitHub theme CSS
# ============================================================
HLJS_CSS="node_modules/highlight.js/styles/github.min.css"
if [ -f "$HLJS_CSS" ]; then
  cp "$HLJS_CSS" "$OUTPUT_DIR/github.min.css"
else
  curl -sL "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.11.1/build/styles/github.min.css" \
    -o "$OUTPUT_DIR/github.min.css"
fi
echo "  github.css:    $(du -h "$OUTPUT_DIR/github.min.css" | awk '{print $1}')"

# ============================================================
# 6. highlight.js GitHub Dark theme CSS (wrapped in dark mode media query)
# ============================================================
HLJS_DARK_CSS="node_modules/highlight.js/styles/github-dark.min.css"
if [ -f "$HLJS_DARK_CSS" ]; then
  # Wrap in prefers-color-scheme: dark media query so it only applies in dark mode
  printf '@media (prefers-color-scheme:dark){' > "$OUTPUT_DIR/github-dark.min.css"
  cat "$HLJS_DARK_CSS" >> "$OUTPUT_DIR/github-dark.min.css"
  printf '}' >> "$OUTPUT_DIR/github-dark.min.css"
else
  curl -sL "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.11.1/build/styles/github-dark.min.css" \
    -o /tmp/github-dark-raw.css
  printf '@media (prefers-color-scheme:dark){' > "$OUTPUT_DIR/github-dark.min.css"
  cat /tmp/github-dark-raw.css >> "$OUTPUT_DIR/github-dark.min.css"
  printf '}' >> "$OUTPUT_DIR/github-dark.min.css"
  rm -f /tmp/github-dark-raw.css
fi
echo "  github-dark:   $(du -h "$OUTPUT_DIR/github-dark.min.css" | awk '{print $1}')"

# ============================================================
# Verify all outputs
# ============================================================
echo ""
echo "Verifying..."
FAIL=0
for f in highlight.min.js temml.min.js mermaid.min.js temml.min.css github.min.css github-dark.min.css; do
  if python3 -c "open('$OUTPUT_DIR/$f','rb').read().decode('utf-8')" 2>/dev/null; then
    echo "  ✓ $f (valid UTF-8)"
  else
    echo "  ✗ $f (INVALID UTF-8!)"
    FAIL=1
  fi
done

# Cleanup
rm -rf "$WORK_DIR"

echo ""
if [ $FAIL -eq 0 ]; then
  echo "Done! All JS/CSS dependencies built successfully."
else
  echo "WARNING: Some files have encoding issues."
  exit 1
fi
