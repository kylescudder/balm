#!/usr/bin/env python3
"""Balm auth settings and hooks for the shared host deployer (deploy_core.py)."""
from pathlib import Path

import deploy_core as core


APP = core.App(
    name='balm-auth', title='Balm-Auth',
    image='ghcr.io/kylescudder/balm-auth', repo='kylescudder/balm',
    image_var='BALM_AUTH_IMAGE', service='balm-auth', app_dir=Path(__file__).resolve().parents[1],
    workflow='deploy-auth.yml')

if __name__ == '__main__':
    core.cli(APP, __file__)
