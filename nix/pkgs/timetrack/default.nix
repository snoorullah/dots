# timetrack: rollup/note/sync CLI + logind event capture. Units live in home/ (timetrack-*), gated by .timetrack.
{ python3, writeShellApplication, symlinkJoin, taskwarrior3, timewarrior, git }:
let
  py = python3.withPackages (ps: with ps; [ sqlite-utils requests jeepney ]);
  cli = writeShellApplication {
    name = "timetrack";
    runtimeInputs = [ py taskwarrior3 timewarrior git ];
    text = ''
      export PYTHONPATH="${./.}:''${PYTHONPATH:-}"
      exec python -m timetrack "$@"
    '';
  };
  logind = writeShellApplication {
    name = "timetrack-logind";
    runtimeInputs = [ py ];
    text = ''exec python3 ${./logind/timetrack-logind.py}'';
  };
in symlinkJoin { name = "timetrack"; paths = [ cli logind ]; }
