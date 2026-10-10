from pathlib import Path
import base64
root=Path(__file__).resolve().parent
page=(root/'index.html').read_text(encoding='utf-8-sig')
page=page.replace('<link rel="stylesheet" href="styles.css">','<style>\n'+(root/'styles.css').read_text(encoding='utf-8-sig')+'\n</style>')
for name in ['domain.js','operations.js','app.js','modules.js','shifts.js','supabase.js']:
 page=page.replace('<script src="'+name+'"></script>','<script>\n'+(root/name).read_text(encoding='utf-8-sig')+'\n</script>')
logo='data:image/png;base64,'+base64.b64encode((root/'assets/puma-logo.png').read_bytes()).decode()
page=page.replace('assets/puma-logo.png',logo)
(root/'PUMA-Vista-Previa.html').write_text(page,encoding='utf-8')
print('Generado PUMA-Vista-Previa.html: archivo autónomo, sin dependencias externas.')
