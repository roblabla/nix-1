source common.sh

requireGit

clearStore

# Intentionally not in a canonical form
# See https://github.com/NixOS/nix/issues/6195
repo=$TEST_ROOT/./git

export _NIX_FORCE_HTTP=1

rm -rf $repo ${repo}-tmp $TEST_HOME/.cache/nix $TEST_ROOT/worktree $TEST_ROOT/shallow $TEST_ROOT/minimal

git init $repo
git -C $repo config user.email "foobar@example.com"
git -C $repo config user.name "Foobar"

echo utrecht > $repo/hello
touch $repo/.gitignore
git -C $repo add hello .gitignore
git -C $repo commit -m 'Bla1'
rev1=$(git -C $repo rev-parse HEAD)
git -C $repo tag -a tag1 -m tag1

echo world > $repo/hello
git -C $repo commit -m 'Bla2' -a
git -C $repo worktree add $TEST_ROOT/worktree
echo hello >> $TEST_ROOT/worktree/hello
rev2=$(git -C $repo rev-parse HEAD)
git -C $repo tag -a tag2 -m tag2

# Fetch a worktree
unset _NIX_FORCE_HTTP
path0=$(nix eval --impure --raw --expr "(builtins.fetchGit file://$TEST_ROOT/worktree).outPath")
path0_=$(nix eval --impure --raw --expr "(builtins.fetchTree { type = \"git\"; url = file://$TEST_ROOT/worktree; }).outPath")
[[ $path0 = $path0_ ]]
path0_=$(nix eval --impure --raw --expr "(builtins.fetchTree git+file://$TEST_ROOT/worktree).outPath")
[[ $path0 = $path0_ ]]
export _NIX_FORCE_HTTP=1
[[ $(tail -n 1 $path0/hello) = "hello" ]]

# Fetch the default branch.
path=$(nix eval --impure --raw --expr "(builtins.fetchGit file://$repo).outPath")
[[ $(cat $path/hello) = world ]]

# Fetch a rev from another branch
git -C $repo checkout -b devtest
echo "different file" >> $TEST_ROOT/git/differentbranch
git -C $repo add differentbranch
git -C $repo commit -m 'Test2'
git -C $repo checkout master
devrev=$(git -C $repo rev-parse devtest)
out=$(nix eval --impure --raw --expr "builtins.fetchGit { url = file://$repo; rev = \"$devrev\"; }" 2>&1) || status=$?
[[ $status == 1 ]]
[[ $out =~ 'Cannot find Git revision' ]]

[[ $(nix eval --raw --expr "builtins.readFile (builtins.fetchGit { url = file://$repo; rev = \"$devrev\"; allRefs = true; } + \"/differentbranch\")") = 'different file' ]]

# In pure eval mode, fetchGit without a revision should fail.
[[ $(nix eval --impure --raw --expr "builtins.readFile (fetchGit file://$repo + \"/hello\")") = world ]]
(! nix eval --raw --expr "builtins.readFile (fetchGit file://$repo + \"/hello\")")

# Fetch using an explicit revision hash.
path2=$(nix eval --raw --expr "(builtins.fetchGit { url = file://$repo; rev = \"$rev2\"; }).outPath")
[[ $path = $path2 ]]

# In pure eval mode, fetchGit with a revision should succeed.
[[ $(nix eval --raw --expr "builtins.readFile (fetchGit { url = file://$repo; rev = \"$rev2\"; } + \"/hello\")") = world ]]

# Fetch again. This should be cached.
mv $repo ${repo}-tmp
path2=$(nix eval --impure --raw --expr "(builtins.fetchGit file://$repo).outPath")
[[ $path = $path2 ]]

[[ $(nix eval --impure --expr "(builtins.fetchGit file://$repo).revCount") = 2 ]]
[[ $(nix eval --impure --raw --expr "(builtins.fetchGit file://$repo).rev") = $rev2 ]]
[[ $(nix eval --impure --raw --expr "(builtins.fetchGit file://$repo).shortRev") = ${rev2:0:7} ]]

# Fetching with a explicit hash should succeed.
path2=$(nix eval --refresh --raw --expr "(builtins.fetchGit { url = file://$repo; rev = \"$rev2\"; }).outPath")
[[ $path = $path2 ]]

path2=$(nix eval --refresh --raw --expr "(builtins.fetchGit { url = file://$repo; rev = \"$rev1\"; }).outPath")
[[ $(cat $path2/hello) = utrecht ]]

mv ${repo}-tmp $repo

# Using a clean working tree should produce the same result.
path2=$(nix eval --impure --raw --expr "(builtins.fetchGit $repo).outPath")
[[ $path = $path2 ]]

# Using an unclean tree should yield the tracked but uncommitted changes.
mkdir $repo/dir1 $repo/dir2
echo foo > $repo/dir1/foo
echo bar > $repo/bar
echo bar > $repo/dir2/bar
git -C $repo add dir1/foo
git -C $repo rm hello

unset _NIX_FORCE_HTTP
path2=$(nix eval --impure --raw --expr "(builtins.fetchGit $repo).outPath")
[ ! -e $path2/hello ]
[ ! -e $path2/bar ]
[ ! -e $path2/dir2/bar ]
[ ! -e $path2/.git ]
[[ $(cat $path2/dir1/foo) = foo ]]

[[ $(nix eval --impure --raw --expr "(builtins.fetchGit $repo).rev") = 0000000000000000000000000000000000000000 ]]
[[ $(nix eval --impure --raw --expr "(builtins.fetchGit $repo).dirtyRev") = "${rev2}-dirty" ]]
[[ $(nix eval --impure --raw --expr "(builtins.fetchGit $repo).dirtyShortRev") = "${rev2:0:7}-dirty" ]]

# ... unless we're using an explicit ref or rev.
path3=$(nix eval --impure --raw --expr "(builtins.fetchGit { url = $repo; ref = \"master\"; }).outPath")
[[ $path = $path3 ]]

path3=$(nix eval --raw --expr "(builtins.fetchGit { url = $repo; rev = \"$rev2\"; }).outPath")
[[ $path = $path3 ]]

# Committing should not affect the store path.
git -C $repo commit -m 'Bla3' -a

path4=$(nix eval --impure --refresh --raw --expr "(builtins.fetchGit file://$repo).outPath")
[[ $path2 = $path4 ]]

[[ $(nix eval --impure --expr "builtins.hasAttr \"rev\" (builtins.fetchGit $repo)") == "true" ]]
[[ $(nix eval --impure --expr "builtins.hasAttr \"dirtyRev\" (builtins.fetchGit $repo)") == "false" ]]
[[ $(nix eval --impure --expr "builtins.hasAttr \"dirtyShortRev\" (builtins.fetchGit $repo)") == "false" ]]

status=0
nix eval --impure --raw --expr "(builtins.fetchGit { url = $repo; rev = \"$rev2\"; narHash = \"sha256-B5yIPHhEm0eysJKEsO7nqxprh9vcblFxpJG11gXJus1=\"; }).outPath" || status=$?
[[ "$status" = "102" ]]

path5=$(nix eval --impure --raw --expr "(builtins.fetchGit { url = $repo; rev = \"$rev2\"; narHash = \"sha256-Hr8g6AqANb3xqX28eu1XnjK/3ab8Gv6TJSnkb1LezG9=\"; }).outPath")
[[ $path = $path5 ]]

# tarball-ttl should be ignored if we specify a rev
echo delft > $repo/hello
git -C $repo add hello
git -C $repo commit -m 'Bla4'
rev3=$(git -C $repo rev-parse HEAD)
nix eval --tarball-ttl 3600 --expr "builtins.fetchGit { url = $repo; rev = \"$rev3\"; }" >/dev/null

# Update 'path' to reflect latest master
path=$(nix eval --impure --raw --expr "(builtins.fetchGit file://$repo).outPath")

# Check behavior when non-master branch is used
git -C $repo checkout $rev2 -b dev
echo dev > $repo/hello

# File URI uses dirty tree unless specified otherwise
path2=$(nix eval --impure --raw --expr "(builtins.fetchGit file://$repo).outPath")
[ $(cat $path2/hello) = dev ]

# Using local path with branch other than 'master' should work when clean or dirty
path3=$(nix eval --impure --raw --expr "(builtins.fetchGit $repo).outPath")
# (check dirty-tree handling was used)
[[ $(nix eval --impure --raw --expr "(builtins.fetchGit $repo).rev") = 0000000000000000000000000000000000000000 ]]
[[ $(nix eval --impure --raw --expr "(builtins.fetchGit $repo).shortRev") = 0000000 ]]
# Making a dirty tree clean again and fetching it should
# record correct revision information. See: #4140
echo world > $repo/hello
[[ $(nix eval --impure --raw --expr "(builtins.fetchGit $repo).rev") = $rev2 ]]

# Committing shouldn't change store path, or switch to using 'master'
echo dev > $repo/hello
git -C $repo commit -m 'Bla5' -a
path4=$(nix eval --impure --raw --expr "(builtins.fetchGit $repo).outPath")
[[ $(cat $path4/hello) = dev ]]
[[ $path3 = $path4 ]]

# Using remote path with branch other than 'master' should fetch the HEAD revision.
# (--tarball-ttl 0 to prevent using the cached repo above)
export _NIX_FORCE_HTTP=1
path4=$(nix eval --tarball-ttl 0 --impure --raw --expr "(builtins.fetchGit $repo).outPath")
[[ $(cat $path4/hello) = dev ]]
[[ $path3 = $path4 ]]
unset _NIX_FORCE_HTTP

# Confirm same as 'dev' branch
path5=$(nix eval --impure --raw --expr "(builtins.fetchGit { url = $repo; ref = \"dev\"; }).outPath")
[[ $path3 = $path5 ]]


# Nuke the cache
rm -rf $TEST_HOME/.cache/nix

# Try again. This should work.
path5=$(nix eval --impure --raw --expr "(builtins.fetchGit { url = $repo; ref = \"dev\"; }).outPath")
[[ $path3 = $path5 ]]

# Fetching from a repo with only a specific revision and no branches should
# not fall back to copying files and record correct revision information. See: #5302
mkdir $TEST_ROOT/minimal
git -C $TEST_ROOT/minimal init
git -C $TEST_ROOT/minimal fetch $repo $rev2
git -C $TEST_ROOT/minimal checkout $rev2
[[ $(nix eval --impure --raw --expr "(builtins.fetchGit { url = $TEST_ROOT/minimal; }).rev") = $rev2 ]]

# Fetching a shallow repo shouldn't work by default, because we can't
# return a revCount.
git clone --depth 1 file://$repo $TEST_ROOT/shallow
(! nix eval --impure --raw --expr "(builtins.fetchGit { url = $TEST_ROOT/shallow; ref = \"dev\"; }).outPath")

# But you can request a shallow clone, which won't return a revCount.
path6=$(nix eval --impure --raw --expr "(builtins.fetchTree { type = \"git\"; url = \"file://$TEST_ROOT/shallow\"; ref = \"dev\"; shallow = true; }).outPath")
[[ $path3 = $path6 ]]
[[ $(nix eval --impure --expr "(builtins.fetchTree { type = \"git\"; url = \"file://$TEST_ROOT/shallow\"; ref = \"dev\"; shallow = true; }).revCount or 123") == 123 ]]

# Explicit ref = "HEAD" should work, and produce the same outPath as without ref
path7=$(nix eval --impure --raw --expr "(builtins.fetchGit { url = \"file://$repo\"; ref = \"HEAD\"; }).outPath")
path8=$(nix eval --impure --raw --expr "(builtins.fetchGit { url = \"file://$repo\"; }).outPath")
[[ $path7 = $path8 ]]

# ref = "HEAD" should fetch the HEAD revision
rev4=$(git -C $repo rev-parse HEAD)
rev4_nix=$(nix eval --impure --raw --expr "(builtins.fetchGit { url = \"file://$repo\"; ref = \"HEAD\"; }).rev")
[[ $rev4 = $rev4_nix ]]

# The name argument should be handled
path9=$(nix eval --impure --raw --expr "(builtins.fetchGit { url = \"file://$repo\"; ref = \"HEAD\"; name = \"foo\"; }).outPath")
[[ $path9 =~ -foo$ ]]

# Specifying a ref without a rev shouldn't pick a cached rev for a different ref
export _NIX_FORCE_HTTP=1
rev_tag1_nix=$(nix eval --impure --raw --expr "(builtins.fetchGit { url = \"file://$repo\"; ref = \"refs/tags/tag1\"; }).rev")
rev_tag1=$(git -C $repo rev-parse refs/tags/tag1)
[[ $rev_tag1_nix = $rev_tag1 ]]
rev_tag2_nix=$(nix eval --impure --raw --expr "(builtins.fetchGit { url = \"file://$repo\"; ref = \"refs/tags/tag2\"; }).rev")
rev_tag2=$(git -C $repo rev-parse refs/tags/tag2)
[[ $rev_tag2_nix = $rev_tag2 ]]
unset _NIX_FORCE_HTTP

# should fail if there is no repo
rm -rf $repo/.git
(! nix eval --impure --raw --expr "(builtins.fetchGit \"file://$repo\").outPath")

# should succeed for a repo without commits
git init $repo
git -C $repo add hello # need to add at least one file to cause the root of the repo to be visible
path10=$(nix eval --impure --raw --expr "(builtins.fetchGit \"file://$repo\").outPath")

# should succeed for a path with a space
# regression test for #7707
repo="$TEST_ROOT/a b"
git init "$repo"
git -C "$repo" config user.email "foobar@example.com"
git -C "$repo" config user.name "Foobar"

echo utrecht > "$repo/hello"
touch "$repo/.gitignore"
git -C "$repo" add hello .gitignore
git -C "$repo" commit -m 'Bla1'
cd "$repo"
path11=$(nix eval --impure --raw --expr "(builtins.fetchGit ./.).outPath")
