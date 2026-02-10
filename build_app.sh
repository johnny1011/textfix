#!/usr/bin/env bash
set -euo pipefail

python -m pip install --upgrade pip
python -m pip install py2app
python setup.py py2app
open dist/TextFix.app
