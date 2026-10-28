# dots-overview: the work-tracking data CLI. Mirrors work into Taskwarrior, detects completion
# by READING the sources, and writes the six JSON files the shell's overview surface draws.
#
# Pure stdlib on purpose, like timetrack: no pip dependency to pin, and every module is
# debuggable with the system python. The runtime tools it shells out to are listed once here;
# herdr and llm are the user's own and are found on PATH, not packaged.
#
# Packaged with writeShellApplication rather than buildPythonApplication for the same reason
# timetrack is: the package is a directory of modules with no setup.py to maintain, and
# PYTHONPATH pointing at the store copy is the whole install.
{ python3, writeShellApplication, taskwarrior3, timewarrior, gh, dbus, xdg-utils }:
writeShellApplication {
  name = "dots-overview";
  runtimeInputs = [ python3 taskwarrior3 timewarrior gh dbus xdg-utils ];
  text = ''
    export PYTHONPATH="${./.}:''${PYTHONPATH:-}"
    exec python -m dots_overview "$@"
  '';
}
