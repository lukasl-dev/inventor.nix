{
  runCommand,
  inventor,
  python3,
  mypy,
  ruff,
}:

runCommand "inventor-checks"
  {
    nativeBuildInputs = [
      inventor
      python3
      mypy
      ruff
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    export PYTHONDONTWRITEBYTECODE=1
    export INVENTOR_TEST_LAUNCHER=${inventor.launcher}/bin/inventor
    cd ${inventor.common.pythonSource}
    mypy --cache-dir "$TMPDIR/mypy" .
    ruff check --no-cache .
    ruff format --check --no-cache .
    python3 -m unittest discover -v
    touch "$out"
  ''
