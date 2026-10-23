"""Keep texture and animated-mesh import settings reproducible on a clean clone.

Only Godot-generated .import sidecars inside this checkout are written.
Source GLBs and images are never changed.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def set_params(path, values):
    original = path.read_text()
    text = original
    for key, value in values.items():
        pattern = rf'(?m)^{re.escape(key)}=.*$'
        if re.search(pattern, text):
            text = re.sub(pattern, lambda _: f'{key}={value}', text)
        else:
            text = text.replace('[params]\n', f'[params]\n{key}={value}\n', 1)
    if text != original:
        path.write_text(text)


def configure():
    changed = []
    for path in sorted((ROOT / 'assets').rglob('*.import')):
        source = path.name.removesuffix('.import')
        params = {}
        if source.endswith(('.png', '.jpg')):
            params = {'mipmaps/generate': 'true', 'process/size_limit': '2048', 'compress/mode': '2'}
            if 'normal' in source:
                params['compress/normal_map'] = '1'
            if source.endswith('_armor_orm.png'):
                kind = source.split('_')[0]
                normal = kind + ('_medieval_knight_3d_model_normal.png' if kind == 'knight' else '_dark_fantasy_creature_3d_model_normal.png')
                params.update({'roughness/mode': '3', 'roughness/src_normal': f'"res://assets/characters/{normal}"'})
            elif source in ['slate_orm.png', 'masonry_orm.png']:
                name = source.removesuffix('_orm.png')
                params.update({'roughness/mode': '3', 'roughness/src_normal': f'"res://assets/textures/{name}_normal.jpg"'})
        elif source in ['knight.glb', 'knight_mobile.glb', 'boss.glb', 'boss_mobile.glb']:
            # Decimation of a skinned fur/armour silhouette causes visible
            # topology pops. These supplied meshes are small enough to retain.
            params = {'meshes/generate_lods': 'false', 'meshes/force_disable_compression': 'true',
                      'import_script/path': '"res://tools/character_import.gd"'}
        if params:
            before = path.read_text()
            set_params(path, params)
            if path.read_text() != before:
                changed.append(str(path.relative_to(ROOT)))
    return changed


if __name__ == '__main__':
    print('Configured', len(configure()), 'asset imports')
