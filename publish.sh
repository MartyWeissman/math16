#!/bin/sh
# publish.sh — publish Math 16A materials to GitHub Pages.
#
#   ./publish.sh              sync PDFs + index.html from the Dropbox working folder, commit, push
#   ./publish.sh --no-push    same, but stop before pushing (look first)
#   M16_SLIDES=1 ./publish.sh also publish lecture-slide PDFs (off by default until decks are ready)
#
# Only these leave the Dropbox folder:  index.html (public build), the lab manual PDF, live-problem PDFs,
# student worksheet PDFs + the lecture digest template, the Teaching Team Manual PDF, and (if M16_SLIDES=1)
# Lecture*.pdf. Never: *_Answers.pdf, .tex, .pptx, anything in Exams/.  Study/ is kept directly in this repo.
set -eu
cd "$(dirname "$0")"
REPO=$(pwd)

# Where the working folder is: Claude's shell sees it under ~/mnt; Marty's Terminal sees it under ~/Dropbox.
for d in "$HOME/mnt/Fall 2026 Materials" "$HOME/Dropbox/MathForLifeSciences/Fall 2026 Materials" "${M16_SRC:-}"; do
  [ -n "$d" ] && [ -d "$d" ] && SRC="$d" && break
done
[ -n "${SRC:-}" ] || { echo "Cannot find the 'Fall 2026 Materials' folder"; exit 1; }
echo "Source: $SRC"

# 1. Public index.html (slide links become 'after lecture' placeholders unless M16_SLIDES=1)
( cd "$SRC" && M16_PUBLIC=1 M16_SLIDES="${M16_SLIDES:-}" M16_OUT="$REPO/index.html" python3 build_index.py )

# 2. Allow-listed copies (rsync --delete keeps each folder an exact mirror of what is allowed)
mkdir -p LiveProblems Worksheets TeachingTeamManual Study
cp -p "$SRC/LabManual_v3_0_Student.pdf" .
rsync -a --delete --include='LiveProblems_L*.pdf' --exclude='*' "$SRC/LiveProblems/" LiveProblems/
rsync -a --delete --exclude='*_Answers.pdf' --include='Worksheet_0[1-9]_*.pdf' --include='LectureDigest_Template.pdf' --exclude='*' "$SRC/Worksheets/" Worksheets/
rsync -a --delete --include='Teaching_Team_Manual.pdf' --exclude='*' "$SRC/Teaching Team Manual/" TeachingTeamManual/
if [ -n "${M16_SLIDES:-}" ]; then
  mkdir -p LectureSlides_16A_Fall2026
  rsync -a --delete --include='Lecture*.pdf' --exclude='*' "$SRC/LectureSlides_16A_Fall2026/" LectureSlides_16A_Fall2026/
fi

# 3. Safety net: refuse to publish keys or sources
bad=$(find . -path ./.git -prune -o \( -name '*_Answers*' -o -name '*.tex' -o -name '*.pptx' -o -name '*.docx' \) -print)
[ -z "$bad" ] || { echo "REFUSING TO PUBLISH — private files present:"; echo "$bad"; exit 1; }

# 4. Every relative link in index.html must exist
missing=$(grep -o 'href="[^"#]*' index.html | sed 's/href="//; s/%20/ /g' | grep -v '^http' | grep . | while read -r f; do [ -e "$f" ] || echo "  $f"; done)
[ -z "$missing" ] || { echo "REFUSING TO PUBLISH — index.html links to files that are not in the repo:"; echo "$missing"; exit 1; }

# 5. Commit + push
git add -A
if git diff --cached --quiet; then echo "Nothing changed since the last publish."; exit 0; fi
echo "Changes:"; git diff --cached --stat | tail -n 25
git commit -q -m "Publish $(date '+%Y-%m-%d %H:%M')"
[ "${1:-}" = "--no-push" ] && { echo "Committed (not pushed)."; exit 0; }
if [ -r .github-token ]; then
  git -c credential.helper= -c credential.helper='!f() { echo username=token; echo "password=$(cat .github-token)"; }; f' push -q origin HEAD:main
else
  git push -q origin HEAD:main
fi
echo "Pushed. GitHub Pages updates in about a minute."
