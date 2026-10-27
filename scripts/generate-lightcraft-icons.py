#!/usr/bin/env python3
"""Export the exact Rust LightCraft vector paths as scalable Apple template PDFs.

Requires rustc and reportlab. No engine build or third-party artwork is used.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
from reportlab.pdfgen import canvas

ROOT = Path(__file__).resolve().parents[1]

def generate(source):
    original = source.read_text()
    names = re.findall(r'^    (\w+),', original.split('struct Pen')[0], re.M)
    recorder = (ROOT / 'scripts/icon-tools/egui-recorder.rs').read_text()
    body = original.split('#[cfg(test)]')[0]
    body = '\n'.join(line for line in body.splitlines() if not line.startswith('//!'))
    calls = '\n'.join(f'println!("ICON:{name}"); paint(&p, r, Icon::{name}, Color32(1.0));' for name in names)
    program = recorder + '\n' + body + '\nfn main() { let p=Painter; let r=Rect::from_min_max(pos2(0.,0.),pos2(20.,20.));' + calls + '}'
    assets = ROOT / 'iLightCraft/Resources/Assets.xcassets'
    with tempfile.TemporaryDirectory(prefix='lightcraft-icons-') as scratch:
        rust = Path(scratch) / 'icons.rs'
        rust.write_text(program)
        binary = Path(scratch) / 'icons'
        subprocess.run(['rustc', '--edition=2024', '-Awarnings', str(rust), '-o', str(binary)], check=True)
        output = subprocess.check_output([str(binary)], text=True)
    drawings = {}
    for line in output.splitlines():
        if line.startswith('ICON:'):
            current = line[5:]
            drawings[current] = []
        else:
            drawings[current].append(json.loads(line))
    # Histogram markers use the desktop's simple clipping triangle.
    drawings['Clipping'] = [dict(kind='path', width=0, alpha=1, fill=True, closed=True, points=[[3,16],[10,4],[17,16]])]
    drawings['RotateClockwise'] = drawings['Rotate']
    for name, commands in drawings.items():
        directory = assets / f'LightCraft-{name}.imageset'
        directory.mkdir(exist_ok=True)
        pdf = canvas.Canvas(str(directory / 'icon.pdf'), pagesize=(20, 20), invariant=1)
        pdf.translate(0,20)
        pdf.scale(1,-1)
        if name == 'RotateClockwise':
            pdf.translate(20,0)
            pdf.scale(-1,1)
        pdf.setLineCap(1)
        pdf.setLineJoin(1)
        for command in commands:
            pdf.setLineWidth(command['width'])
            pdf.setStrokeAlpha(command['alpha'])
            pdf.setFillAlpha(command['alpha'])
            fill = int(command['fill'])
            stroke = 1-fill
            if command['kind'] == 'path':
                path = pdf.beginPath()
                for i, (x,y) in enumerate(command['points']):
                    (path.moveTo if i == 0 else path.lineTo)(x,y)
                if command['closed']:
                    path.close()
                pdf.drawPath(path, stroke=stroke, fill=fill)
            elif command['kind'] == 'circle':
                pdf.circle(command['x'],command['y'],command['r'],stroke=stroke,fill=fill)
            else:
                pdf.roundRect(command['x'],command['y'],command['w'],command['h'],command['round'],stroke=stroke,fill=fill)
        pdf.showPage()
        pdf.save()
        metadata = {'images':[{'filename':'icon.pdf','idiom':'universal'}], 'info':{'author':'xcode','version':1}, 'properties':{'preserves-vector-representation':True,'template-rendering-intent':'template'}}
        (directory / 'Contents.json').write_text(json.dumps(metadata,indent=2)+'\n')
    manifest = {'source':'LightCraft crates/ui-egui/src/icons.rs','sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'icons':list(drawings)}
    (ROOT / 'scripts/icon-tools/source.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'Exported {len(drawings)} vector icons from {source}')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=ROOT / 'scripts/icon-tools/lightcraft-icons.rs')
    generate(parser.parse_args().source)
