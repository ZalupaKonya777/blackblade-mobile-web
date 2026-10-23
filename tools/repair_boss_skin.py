"""Compatibility entry point; the shared repair also prepares the knight skin."""
from repair_mobile_skins import repair,ROOT
import json
if __name__=='__main__':
    report=[repair(kind) for kind in ['knight','boss']]
    (ROOT/'artifacts/mobile_skin_repair.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))
