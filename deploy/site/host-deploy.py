#!/usr/bin/env python3
"""Balm marketing site settings and hooks for the shared host deployer (deploy_core.py)."""
from pathlib import Path

import deploy_core as core


APP = core.App(
    name='balm-site', title='Balm-Site',
    image='ghcr.io/kylescudder/balm-site', repo='kylescudder/balm',
    image_var='BALM_SITE_IMAGE', service='balm-site', app_dir=Path(__file__).resolve().parents[2],
    workflow='deploy-site.yml',
    compose_file='compose.site.yaml')

if __name__ == '__main__':
    core.cli(APP, __file__)
