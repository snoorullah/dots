# dots-inbox: triage, the touchpoint ledger and prepared work for mail and Slack.
#
# Pure stdlib, like timetrack and dots-overview: a directory of modules on PYTHONPATH.
# notmuch reads the encrypted mail store (dots-mail); nothing here can send anything:
# no SMTP is configured on this machine, and the Slack checker runs with the send tools
# disallowed.
{ python3, writeShellApplication, notmuch, libnotify, glib }:
writeShellApplication {
  name = "dots-inbox";
  runtimeInputs = [ python3 notmuch libnotify glib ];
  text = ''
    export PYTHONPATH="${./.}:''${PYTHONPATH:-}"
    exec python -m dots_inbox "$@"
  '';
}
