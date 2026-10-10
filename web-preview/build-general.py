"""Package the separate responsive general-manager web entry without changing preview."""
from pathlib import Path
import base64

root = Path(__file__).resolve().parent
page = (root / 'gerente.html').read_text(encoding='utf-8-sig')
for name in ['styles.css', 'gerente.css']:
    page = page.replace(f'<link rel="stylesheet" href="{name}">', '<style>\n' + (root / name).read_text(encoding='utf-8-sig') + '\n</style>')
for name in ['domain.js', 'operations.js', 'app.js', 'modules.js', 'shifts.js', 'supabase.js', 'gerente.js']:
    page = page.replace(f'<script src="{name}"></script>', '<script>\n' + (root / name).read_text(encoding='utf-8-sig') + '\n</script>')
logo = 'data:image/png;base64,' + base64.b64encode((root / 'assets/puma-logo.png').read_bytes()).decode()
page = page.replace('assets/puma-logo.png', logo)
(root / 'PUMA-Gerente-General.html').write_text(page, encoding='utf-8')
print('Generated PUMA-Gerente-General.html; mobile preview preserved.')
