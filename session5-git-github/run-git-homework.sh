#!/bin/bash
# run-git-homework.sh
# Performs the two Git homework tasks inside this repository, prints every
# command before its output, saves the whole transcript to
# outputs/transcript.txt, and then assembles README.md from it.
#
# Run it ONCE from anywhere inside the repo, on branch main, with a clean tree:
#   bash session5-git-github/run-git-homework.sh
set -u
cd "$(git rev-parse --show-toplevel)" || exit 1
DIR=session5-git-github
OUT=$DIR/outputs
mkdir -p "$OUT"
T=$OUT/transcript.txt

# ---- safety checks -------------------------------------------------------
if [ "$(git branch --show-current)" != "main" ]; then
  echo "Please switch to main first (git checkout main)."; exit 1
fi
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "Tracked files have uncommitted changes. 'git commit -a' would sweep them in."
  echo "Commit or stash these first:"; git status --short --untracked-files=no; exit 1
fi
if git rev-parse --verify feature-branch >/dev/null 2>&1; then
  echo "Branch feature-branch already exists; this script was already run."; exit 1
fi
: > "$T"

run() { printf '\n$ %s\n' "$*" | tee -a "$T"; bash -c "$*" 2>&1 | tee -a "$T"; }
say() { printf '\n### %s\n' "$*" | tee -a "$T"; }

say "Environment"
run 'git --version; git branch --show-current; git log --oneline -1'

# ======================= TASK 1 =========================================
say "TASK 1 - Step 1: create a new file and commit it (a new file must be staged with git add)"
run 'echo "line 1" > session5-git-github/demo.txt'
run 'git status --short session5-git-github'
run 'git add session5-git-github/demo.txt && git commit -m "git task 1: create demo.txt"'

say "TASK 1 - Step 2: modify the tracked file and create an untracked file"
run 'echo "line 2" >> session5-git-github/demo.txt'
run 'echo "this file has never been added" > session5-git-github/untracked.txt'
run 'git status'

say "TASK 1 - Step 3: git commit -m with nothing staged does NOT commit"
run 'git commit -m "git task 1: this should fail, nothing is staged"; echo "exit code: $?"'
run 'git log --oneline -1'

say "TASK 1 - Step 4: git commit -a -m stages every modified tracked file and commits in one step"
run 'git commit -a -m "git task 1: modify demo.txt with commit -a -m"'
run 'git show --stat --oneline HEAD | cat'

say "TASK 1 - Step 5: -a ignored the untracked file; it still needs git add"
run 'git status --short session5-git-github'
run 'git add session5-git-github/untracked.txt && git commit -m "git task 1: add untracked.txt explicitly with git add"'
run 'git log --oneline -3'

# ======================= TASK 2 =========================================
say "TASK 2 - Step 6: three commits on main"
run 'echo "main change 1" > session5-git-github/file1.txt && git add session5-git-github/file1.txt && git commit -m "main commit 1: add file1"'
run 'echo "main change 2" > session5-git-github/file2.txt && git add session5-git-github/file2.txt && git commit -m "main commit 2: add file2"'
run 'echo "main change 3" > session5-git-github/file3.txt && git add session5-git-github/file3.txt && git commit -m "main commit 3: add file3"'
run 'git log --oneline -4'

say "TASK 2 - Step 7: create a new branch and make three commits on it"
run 'git checkout -b feature-branch'
run 'echo "feature A" > session5-git-github/featureA.txt && git add session5-git-github/featureA.txt && git commit -m "feature commit A"'
run 'echo "IMPORTANT BUGFIX" > session5-git-github/bugfix.txt && git add session5-git-github/bugfix.txt && git commit -m "feature commit B: the bugfix to cherry-pick"'
run 'echo "feature C" > session5-git-github/featureC.txt && git add session5-git-github/featureC.txt && git commit -m "feature commit C"'
run 'git log --oneline -4'

say "TASK 2 - Step 8: identify the commit to cherry-pick (the middle one, commit B)"
run 'git log --oneline --grep="feature commit B" -1'
PICK=$(git log --format=%h --grep="feature commit B" -1)

say "TASK 2 - Step 9: back on main, the bugfix does not exist yet"
run 'git checkout main'
run 'ls session5-git-github'
run 'git log --oneline -1'

say "TASK 2 - Step 10: cherry-pick commit B onto main"
run "git cherry-pick $PICK"

say "TASK 2 - Step 11: verify the change is on main, and only that change"
run 'ls session5-git-github'
run 'cat session5-git-github/bugfix.txt'
run 'git log --oneline -3'
run 'git log --oneline --graph --all -10'
run "git show --stat --oneline $PICK | cat"
run 'git show --stat --oneline HEAD | cat'
run 'git branch'

# ======================= README =========================================
GITV=$(git --version)
{
cat <<'EOF'
# Git and GitHub - Homework

**Name:** Rudhar Bajaj
EOF
echo "**Environment:** macOS 26.5.2, \`$GITV\`, repository \`rudhar07/devops-heros\` (fork of the course repo), working directory \`session5-git-github/\`"
cat <<'EOF'

Two tasks: the difference between `git commit -m` and `git commit -a -m`, and
moving one specific commit between branches with `git cherry-pick`. Everything
was done inside this repository, so the commits and the `feature-branch` are
visible in the GitHub history. The full transcript is in
[`outputs/transcript.txt`](outputs/transcript.txt) and the script that ran the
steps is [`run-git-homework.sh`](run-git-homework.sh).

## Contents

1. [Task 1 - git commit -m vs git commit -a -m](#task-1---git-commit--m-vs-git-commit--a--m)
2. [Task 2 - git cherry-pick](#task-2---git-cherry-pick)
3. [Key takeaways](#key-takeaways)
4. [Summary](#summary)

---

## Task 1 - git commit -m vs git commit -a -m

### The idea

Git has three places a change can be:

```text
working directory  --git add-->  staging area (index)  --git commit-->  repository
```

`git commit -m "msg"` records only what is already in the staging area.
`git commit -a -m "msg"` first stages every **tracked** file that was modified
or deleted, then commits, so it saves the `git add` step. The important word is
*tracked*: a brand-new file that Git has never seen is not touched by `-a`.

### Steps

| Step | Command | Expected result |
| --- | --- | --- |
| 1 | `echo "line 1" > demo.txt`, `git add demo.txt`, `git commit -m` | new file committed, now tracked |
| 2 | `echo "line 2" >> demo.txt`, `echo ... > untracked.txt`, `git status` | demo.txt "not staged", untracked.txt "untracked" |
| 3 | `git commit -m "..."` | fails: nothing staged, exit code 1 |
| 4 | `git commit -a -m "..."` | succeeds: demo.txt staged and committed in one step |
| 5 | `git status`, `git add untracked.txt`, `git commit -m` | untracked.txt was ignored by `-a` and needs `git add` |

### Task 1 transcript (real output)

```text
EOF
sed -n '1,/^### TASK 2 - Step 6/p' "$T" | sed '$d'
cat <<'EOF'
```

### What I understood

In step 3 Git refused to commit and printed the modified file under "Changes
not staged for commit", because `-m` only looks at the staging area and it was
empty. In step 4 the same commit message worked with `-a`, and `git show --stat`
confirmed that `demo.txt` was the only file in that commit. In step 5
`untracked.txt` was still listed as untracked after the `-a` commit, which proves
that `-a` only auto-stages files Git already tracks. `-a` is convenient for
small edits, but `git add` plus `git commit -m` gives control over exactly which
changes go into a commit, and it is the only way to include a new file.

---

## Task 2 - git cherry-pick

### The idea

`git cherry-pick <commit>` takes the change introduced by one commit and applies
it as a new commit on the current branch. Unlike `git merge`, it does not bring
the rest of the other branch's history. The typical use is a bug fix that sits
on a feature branch which is not ready to merge, but the fix is needed on main
now.

### Steps

| Step | What happens |
| --- | --- |
| 6 | three commits on `main` (`file1.txt`, `file2.txt`, `file3.txt`) |
| 7 | `git checkout -b feature-branch`, three commits A, B, C (`featureA.txt`, `bugfix.txt`, `featureC.txt`) |
| 8 | `git log` to find the hash of commit B, the one to cherry-pick |
| 9 | `git checkout main`, `ls` shows no `bugfix.txt` yet |
| 10 | `git cherry-pick <hash of B>` |
| 11 | `ls`, `cat bugfix.txt`, `git log --graph --all` to verify |

### Task 2 transcript (real output)

```text
EOF
sed -n '/^### TASK 2 - Step 6/,$p' "$T"
cat <<'EOF'
```

### What I understood

Before the cherry-pick, `ls` on `main` showed no `bugfix.txt`, and afterwards it
was there with the right content, while `featureA.txt` and `featureC.txt` were
still absent. The graph shows both branches sharing history up to "main commit
3", then diverging, and "feature commit B" appearing twice: once on
`feature-branch` and once on `main` with a **different hash**. The hash is
different because a commit ID is computed from the content *and* the metadata,
including the parent commit, and the cherry-picked copy has "main commit 3" as
its parent instead of "feature commit A". So cherry-pick copies a change, it
does not move the original. If `feature-branch` is merged later, Git notices the
identical change and normally does not complain.

---

## Key takeaways

- `git commit -m` commits the staging area; `git commit -a -m` first stages
  modified and deleted tracked files. Neither touches untracked files.
- `git status` tells me which of the three areas a change is in.
- `git cherry-pick <hash>` copies one commit onto the current branch and gives
  it a new hash; use `git log --oneline` to find the hash and
  `git log --graph --all` to see the result.
- `git show --stat <hash>` is the quickest way to see what a commit changed.

## Summary

| Assignment requirement | Where it is satisfied |
| --- | --- |
| Practice `git commit -a -m "message"` | Task 1, step 4 |
| Understand the difference between `-a -m` and `-m` | Task 1 idea and "What I understood" |
| Test both commands and observe the difference | Task 1 steps 3 and 4 (failure, then success) |
| Create 2-4 commits in main | Task 2, step 6 (three commits) |
| Use `git log` to view the commits | Task 2, steps 6 and 7 |
| Create a new branch, make 2-3 commits | Task 2, step 7 (`feature-branch`, three commits) |
| Use `git log` to identify a specific commit | Task 2, step 8 |
| Cherry-pick one commit into main | Task 2, step 10 |
| Verify the change is available in main | Task 2, step 11 |
| Screenshots or an .md file with commands and output | This file and `outputs/transcript.txt` |
EOF
} > "$DIR/README.md"

echo
echo "Done. Transcript: $T"
echo "README written: $DIR/README.md"
echo "Next: git add session5-git-github && git commit -m 'session5: git homework write-up' && git push -u origin main && git push -u origin feature-branch"
