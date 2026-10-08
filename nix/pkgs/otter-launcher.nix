{ lib, rustPlatform, fetchFromGitHub }:
rustPlatform.buildRustPackage {
  pname = "otter-launcher"; version = "0.7.5";
  # not on crates.io; live binary was `cargo install --git` at this rev
  src = fetchFromGitHub { owner = "kuokuo123"; repo = "otter-launcher"; rev = "8f41dd4b3a99d31c21c31c9f9d06711234cf52c1"; hash = "sha256-qXiboL3BSHXH3sndD0slH+Fgo3/crymBLPz3ZMgxRUg="; };
  cargoHash = "sha256-qYzCMW1UCgX5Um1gxMhJpSPeD7962HP5A6uV4ggy9OA=";
  meta.mainProgram = "otter-launcher";
}
