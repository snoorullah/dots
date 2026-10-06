{ python3Packages, fetchPypi, lib }:
python3Packages.buildPythonPackage rec {
  pname = "adhanpy"; version = "1.0.5";
  pyproject = true;
  src = fetchPypi { inherit pname version; hash = "sha256-m2Zw+NVj1h1Pn95YEWXL5pLJF3ELaUy2teITD/yQJoA="; };
  build-system = [ python3Packages.setuptools ];
  pythonImportsCheck = [ "adhanpy" ];
}
