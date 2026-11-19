# Zen: one profile, four Spaces, extensions and their settings, all declared here.
# Spaces follow 8 days of ActivityWatch (2026-11-04): PR review 16h, company consoles ~12h, platform consoles ~3h
# (peaking 02:00-03:00 IST), AI and docs ~4h; personal browsing < 0.3h, so there is no Personal Space.
# ⚠ Spaces, pins and shortcuts are written into the session files only while Zen is closed; with Zen open,
# home-manager skips them and says so. Close Zen, switch, reopen.
{ config, pkgs, lib, gpu, inputs, ... }:
let
  # Same GPU wrapper as home.nix (spec D2).
  glhost = inputs.nix-gl-host.packages.${pkgs.system}.default;
  gl = drv:
    if gpu == "nvidia" then pkgs.symlinkJoin {
      name = "${drv.name}-nixglhost"; paths = [ drv ]; nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''for b in $out/bin/*; do t=$(readlink -f "$b"); rm "$b"; makeWrapper ${glhost}/bin/nixglhost "$b" --add-flags "$t"; done'';
    }
    else if gpu == "mesa" then config.lib.nixGL.wrap drv
    else drv;

  amo = slug: "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
  force = slug: { installation_mode = "force_installed"; install_url = amo slug; };

  # Policies must go on the UNWRAPPED package: Gecko reads distribution/policies.json next to the real binary,
  # so the wrapper's copy (what home.nix used to pass) was never loaded.
  policies = {
    ExtensionSettings = {
      "tridactyl.vim@cmcaine.co.uk" = force "tridactyl-vim";                        # vim keys everywhere
      "{81b74d53-9416-4fb3-afa2-ab46684b253b}" = force "tabwrangler";               # close tabs idle 12h (set once, see below)
      "jid0-RvYT2rGWfM8q5yWxIxAHYAeo5Qg@jetpack" = force "duplicate-tabs-closer";   # jump to the open copy
      "leechblockng@proginosko.com" = force "leechblock-ng";                        # feeds blocked 24/7
      "uBlock0@raymondhill.net" = force "ublock-origin";
      "{ef87d84c-2127-493f-b952-5b4e744245bc}" = force "aw-watcher-web";             # ActivityWatch / timetrack
      "brotab_mediator@example.org" = force "brotab";                               # `bt` tab control
    };
    # browser.storage.managed: re-applied on every start, so edits in the extension's own page revert.
    "3rdparty".Extensions = {
      "jid0-RvYT2rGWfM8q5yWxIxAHYAeo5Qg@jetpack" = {
        onDuplicateTabDetected.value = "A";   # close the new copy automatically
        onRemainingTab.value = "A";           # and switch to the one already open
        ignoreHashPart.value = true;
      };
      # Feeds, not content: home pages, Shorts and timelines are blocked; a video, playlist or Reddit thread
      # you open on purpose still loads. 24/7 (owner, 2026-11-04). A blocked page waits 60s, then allows 5 min.
      "leechblockng@proginosko.com" = {
        numSets = 1;
        setName1 = "Feeds";
        sites1 = lib.concatStringsSep " " [
          "youtube.com" "+youtube.com/watch" "+youtube.com/playlist" "+music.youtube.com"
          "reddit.com" "+reddit.com/r/*/comments/"
          "x.com" "twitter.com" "instagram.com" "facebook.com" "tiktok.com"
        ];
        times1 = "0000-2400";
        days1 = [ true true true true true true true ];
        delayFirst1 = true;
        delaySecs1 = "60";
        delayAllowMins1 = "5";
      };
    };
  };

  wrapZen = import "${inputs.zen-browser}/wrap-zen.nix" pkgs.wrapFirefox;
  zen = gl (wrapZen (inputs.zen-browser.packages.${pkgs.system}.beta-unwrapped.override { extraPolicies = policies; }) {
    icon = "zen-browser";
  });
  # Native messaging hosts (wrapFirefox's own list never reached the unwrapped binary). Zen reads both dirs.
  #  * tridactyl: lets Tridactyl read ~/.config/tridactyl/tridactylrc
  #  * brotab: `bt` tab control; points at the profile's bt_mediator so it follows the patched brotab in home.nix
  brotabHost = builtins.toJSON {
    name = "brotab_mediator"; type = "stdio";
    description = "This mediator exposes interface over TCP to control browser's tabs";
    path = "${config.home.profileDirectory}/bin/bt_mediator";
    allowed_extensions = [ "brotab_mediator@example.org" ];
  };
  nativeHosts = dir: {
    "${dir}/native-messaging-hosts/tridactyl.json".source = "${pkgs.tridactyl-native}/lib/mozilla/native-messaging-hosts/tridactyl.json";
    "${dir}/native-messaging-hosts/brotab_mediator.json".text = brotabHost;
  };
  # The live config launches `zen` / `zen-browser`; the flake ships `zen-beta`.
  zenNames = pkgs.runCommand "zen-compat-links" { } ''
    mkdir -p $out/bin
    ln -s ${zen}/bin/zen-beta $out/bin/zen
    ln -s ${zen}/bin/zen-beta $out/bin/zen-browser
  '';

  work = 2;   # existing container "Work" (containers.json, user-context-work); one login set for all work Spaces
  space = {
    review   = "7cefcce7-6e67-4eb3-96f9-5bf5b110bf5a";   # was "PR Reviews"
    company  = "7cb8fa15-b3bd-4c26-8814-c0f3091a281e";
    platform = "11c542f7-9068-4467-8be6-43448d1d6fe7";   # was "Platform"
    learn    = "53a77283-b909-4866-9365-8f18d8691d3d";   # was "Learning"
  };
  pin = id: position: url: { inherit id position url; };
in {
  imports = [ inputs.zen-browser.homeModules.beta ];

  home.packages = [ zen zenNames ];
  home.file = nativeHosts ".mozilla" // nativeHosts ".zen";

  # The module keeps profiles in ~/.config/zen; this profile has always lived in ~/.zen. Point one at the other
  # once, and move the hand-made profiles.ini aside so home-manager can own it.
  home.activation.zenLegacyProfileDir = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    if [ -d "$HOME/.zen" ] && [ ! -e "$HOME/.config/zen" ]; then
      run ln -s "$HOME/.zen" "$HOME/.config/zen"
      [ -f "$HOME/.zen/profiles.ini" ] && [ ! -L "$HOME/.zen/profiles.ini" ] && run mv "$HOME/.zen/profiles.ini" "$HOME/.zen/profiles.ini.pre-hm"
    fi
  '';

  programs.zen-browser = {
    enable = true;
    package = null;   # installed above: GPU wrapper + policies on the unwrapped build

    profiles.default = {
      id = 0;
      name = "Default Profile";
      path = "10egd1o7.Default Profile";
      isDefault = true;

      settings = {
        "zen.welcome-screen.seen" = true;
        "extensions.autoDisableScopes" = 0;                    # policy extensions start enabled
        "privacy.userContext.enabled" = true;
        "privacy.userContext.ui.enabled" = true;
        "permissions.default.desktop-notification" = 2;        # no "allow notifications?" prompts
        "media.autoplay.default" = 5;                          # nothing plays until you press play
        "signon.rememberSignons" = true;                       # Zen is the password manager now (KeePassXC removed 2026-11-20)
        "signon.autofillForms" = true;
        "zen.tab-unloader.enabled" = true;                     # idle tabs free memory after 30 min
        "zen.tab-unloader.timeout-minutes" = 30;
        "browser.newtabpage.activity-stream.showSponsored" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
      };

      spaces = {
        "Review" = {
          id = space.review; position = 1000; icon = "🔍"; container = work;
          pins = {
            "ovh-infra PRs"   = pin "9709be17-87b3-44e9-9809-6d3c5b48d68d" 101 "https://github.com/ProficientnowTech/ovh-infra/pulls";
            "pnow-ats-v2 PRs" = pin "64aa87d4-ffba-4ecb-84b8-8850a1f867c9" 102 "https://github.com/ProficientnowTech/pnow-ats-v2/pulls";
            "pnow-core PRs"   = pin "116705df-db59-4f82-bb9e-e9f24888f308" 103 "https://github.com/ProficientnowTech/pnow-core/pulls";
            "Review requests" = pin "2296db28-b063-4f24-bafe-47276f2ab7c3" 104 "https://github.com/pulls/review-requested";
            "SonarCloud"      = pin "7850818c-9278-430b-a114-0cc34fa6c5c8" 105 "https://sonarcloud.io/projects";
          };
          routes."GitHub org".reference = "github.com/ProficientnowTech";
          routes."SonarCloud".reference = "sonarcloud.io";
        };
        "Company" = {
          id = space.company; position = 2000; icon = "🏢"; container = work;
          pins = {
            "Helpdesk"        = pin "65268bc9-7d11-4169-9c0b-a25ecee1cdef" 201 "https://erp.proficientnow.com/helpdesk/tickets";
            "ERP projects"    = pin "69a81ad3-5fb8-4441-9e66-01abff7b6d34" 202 "https://erp.proficientnow.com/desk/project";
            "ERP dev"         = pin "e5498899-bde1-437f-8f44-c16bcfb3fdfa" 203 "https://erp-dev.proficientnow.com/desk/engineering";
            "Azure PIM"       = pin "9f888e56-66ca-4336-b97e-a8bbf76c907e" 204 "https://portal.azure.com/#view/Microsoft_Azure_PIMCommon/ActivationMenuBlade/~/aadmigratedroles";
            "Vercel"          = pin "5d7eddba-5d7c-4916-bd8e-abb86dd634fa" 205 "https://vercel.com/proficient-now-tech";
            "Cloudflare"      = pin "c9286855-1a07-4c2d-8a0f-b6896a42289e" 206 "https://dash.cloudflare.com/";
          };
          routes = lib.genAttrs [ "erp.proficientnow.com" "erp-dev.proficientnow.com" "portal.azure.com" "vercel.com"
            "dash.cloudflare.com" "outlook.cloud.microsoft" "teams.cloud.microsoft" "slack.com" ] (r: { reference = r; });
        };
        "Platform" = {
          id = space.platform; position = 3000; icon = "🛠️"; container = work;
          pins = {
            "Argo CD"         = pin "14b0718e-a43b-436e-847f-4d7882f18451" 301 "https://argocd.aps2.pnats.cloud/applications";
            "Kargo"           = pin "b4ac7109-2692-4fb1-9af6-496cef1c0103" 302 "https://kargo.aps2.pnats.cloud/project/kargo-pnats";
            "Argo Workflows"  = pin "a5229c9f-3a1b-4e85-b9e4-3f1864295b4f" 303 "https://workflows.aps2.pnats.cloud/workflows/";
            "Forgejo"         = pin "22ce3d0a-9a84-4af3-8b67-54f92f4e568b" 304 "https://forgejo.aps2.pnats.cloud/pnats/-/packages";
            "Vault"           = pin "86a9dd74-66fc-4c8b-9a71-f53591d0805f" 305 "https://vault.aps2.pnats.cloud/ui/";
            "HyperDX"         = pin "01b5a0c6-b6a2-4f22-bd30-96ff63c30230" 306 "https://hyperdx.aps2.pnats.cloud/";
            "PVE xl02"        = pin "b12dd667-75df-43bb-90a1-b115c60ce87f" 307 "https://192.168.100.131:8006/";
          };
          routes."aps2 consoles" = { reference = "https?://[^/]*\\.aps2(-dev)?\\.pnats\\.cloud"; matchType = "regex"; };
          routes."On-prem mgmt" = { reference = "https?://192\\.168\\.100\\."; matchType = "regex"; };
          routes."RFCs".reference = "rfc.pnats.cloud";
        };
        "AI & Learn" = {
          id = space.learn; position = 4000; icon = "📚";   # default container: your own Claude login
          pins = {
            "Claude Code"     = pin "121c496b-4631-4899-8dc0-4ce7a8136d9a" 401 "https://claude.ai/code";
            "Frappe docs"     = pin "c3baae13-d589-4fdd-aba2-a8bae055d3b5" 402 "https://docs.frappe.io/framework";
          };
          routes = lib.genAttrs [ "claude.ai" "youtube.com" "docs.frappe.io" "readthedocs.io" ] (r: { reference = r; });
        };
      };

      # Essentials stay visible in every Space.
      pins = {
        "Outlook" = { id = "c8e3349d-5665-4290-843a-dc8d86ac498f"; url = "https://outlook.cloud.microsoft/mail/"; position = 1; isEssential = true; container = work; };
        "Teams"   = { id = "b829cb2f-6489-4335-b67c-87e9b02bdb61"; url = "https://teams.cloud.microsoft/";        position = 2; isEssential = true; container = work; };
        "Slack"   = { id = "7755a985-5f73-4641-b62b-7d07854c0e74"; url = "https://pnats.slack.com/";              position = 3; isEssential = true; container = work; };
        "Claude"  = { id = "808ba9b7-c51b-471c-890c-eca4728fafcd"; url = "https://claude.ai/new";                 position = 4; isEssential = true; };
      };
      # Every pin not declared here becomes an ordinary tab (not deleted), so Tab Wrangler can retire it.
      pinsForce = true;
      pinsForceAction = "demote";

      spaceRouting.defaultExternalRoute = "most-recent-space";

      # Space N on Ctrl+Alt+N; nothing in Hyprland or Zen uses these.
      keyboardShortcuts = lib.imap1 (n: _: {
        id = "zen-workspace-switch-${toString n}"; key = toString n; modifiers = { control = true; alt = true; };
      }) [ 1 2 3 4 ];
      keyboardShortcutsVersion = 20;

      # Replaces all bookmarks on every start. The three real ones that existed on 2026-11-04 are kept under Reference.
      bookmarks = {
        force = true;
        settings = [
          { name = "Review"; bookmarks = [
            { name = "ovh-infra issues"; url = "https://github.com/ProficientnowTech/ovh-infra/issues"; }
            { name = "pnats-deploy PRs"; url = "https://github.com/ProficientnowTech/pnats-deploy/pulls"; }
            { name = "rfcs PRs"; url = "https://github.com/ProficientnowTech/rfcs/pulls"; }
            { name = "Org security"; url = "https://github.com/organizations/ProficientnowTech/settings/security_products"; }
            { name = "Org apps"; url = "https://github.com/organizations/ProficientnowTech/settings/installations"; }
          ]; }
          { name = "Company"; bookmarks = [
            { name = "ERP desk"; url = "https://erp.proficientnow.com/desk"; }
            { name = "ERP dev /pn"; url = "https://erp-dev.proficientnow.com/pn"; }
            { name = "Slack admin"; url = "https://pnats.slack.com/admin"; }
            { name = "Slack apps"; url = "https://api.slack.com/apps"; }
            { name = "Monitoring"; url = "https://monitoring.proficientnow.com/"; }
            { name = "GLPI assets"; url = "https://glp.proficientnow.com/front/dashboard_assets.php"; }
            { name = "My sign-ins"; url = "https://mysignins.microsoft.com/"; }
          ]; }
          { name = "Platform"; bookmarks = [
            { name = "MinIO"; url = "https://minio.aps2.pnats.cloud/"; }
            { name = "dev app"; url = "https://app.aps2-dev.pnats.cloud/"; }
            { name = "RFCs"; url = "https://rfc.pnats.cloud/"; }
            { name = "PVE l01"; url = "https://192.168.100.130:8006/"; }
            { name = "PVE xl01"; url = "https://192.168.100.132:8006/"; }
            { name = "BMC l01"; url = "https://192.168.100.140/"; }
          ]; }
          { name = "Reference"; bookmarks = [
            { name = "Argo CD ApplicationSet"; url = "https://argo-cd.readthedocs.io/en/release-3.5/operator-manual/applicationset/"; }
            { name = "Argo Workflows"; url = "https://argo-workflows.readthedocs.io/en/latest/"; }
            { name = "ERPNext docs"; url = "https://docs.frappe.io/erpnext"; }
            { name = "Carvel kapp"; url = "https://carvel.dev/kapp/"; }
            { name = "Atlantis"; url = "https://www.runatlantis.io/"; }
            { name = "agent-sandbox"; url = "https://github.com/kubernetes-sigs/agent-sandbox"; }
          ]; }
        ];
      };
    };
  };

  # Tridactyl: vim keys with Colemak-DH home-row hints. `sanitise` first, so this file is the whole config.
  xdg.configFile."tridactyl/tridactylrc".text = ''
    sanitise tridactyllocal tridactylsync
    set hintchars arstneiogm
    set smoothscroll true
    set modeindicator true
    set newtab about:blank
    " Apps with their own keyboard shortcuts: Tridactyl stays out (Shift+Esc toggles it back).
    autocmd DocStart outlook.cloud.microsoft mode ignore
    autocmd DocStart teams.cloud.microsoft mode ignore
    autocmd DocStart slack.com mode ignore
    autocmd DocStart excalidraw.com mode ignore
    " Leave Ctrl+Alt+1..4 to Zen (Space switching).
    unbind <C-A-1>
    unbind <C-A-2>
    unbind <C-A-3>
    unbind <C-A-4>
  '';
}
