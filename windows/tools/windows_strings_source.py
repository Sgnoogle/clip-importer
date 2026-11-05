#!/usr/bin/env python3
"""Sorgente delle frasi solo Windows: genera windows/strings.windows.json.
Uso: python3 windows/tools/windows_strings_source.py
(Si può anche modificare direttamente strings.windows.json: questo file serve solo a tenerle in ordine.)"""
import json, os

T = {
 " (moved to the Recycle Bin)": {
  "it": " (nel Cestino)", "es": " (a la Papelera de reciclaje)", "fr": " (dans la Corbeille)", "de": " (in den Papierkorb)",
  "pt": " (para a Lixeira)", "ru": " (в Корзину)", "ja": "（ごみ箱へ）", "ko": " (휴지통으로)", "zh": "（移到回收站）"},
 " · P pick · X reject · U unflag · Space preview · Del delete": {
  "it": " · P scegli · X scarta · U togli etichetta · Spazio anteprima · Canc elimina",
  "es": " · P seleccionar · X rechazar · U quitar marca · Espacio vista previa · Supr eliminar",
  "fr": " · P retenir · X rejeter · U retirer le drapeau · Espace aperçu · Suppr supprimer",
  "de": " · P auswählen · X ablehnen · U Markierung entfernen · Leertaste Vorschau · Entf löschen",
  "pt": " · P escolher · X rejeitar · U tirar marca · Espaço pré-visualizar · Del apagar",
  "ru": " · P отобрать · X отклонить · U снять флажок · Пробел просмотр · Del удалить",
  "ja": " · P 採用 · X 除外 · U フラグ解除 · Space プレビュー · Del 削除",
  "ko": " · P 선택 · X 거부 · U 플래그 해제 · Space 미리 보기 · Del 삭제",
  "zh": " · P 留用 · X 排除 · U 取消标记 · 空格 预览 · Del 删除"},
 "Click: pick (P) · Alt+click: reject (X) · right-click: more options": {
  "it": "Clic: scegli (P) · Alt+clic: scarta (X) · clic destro: altre opzioni",
  "es": "Clic: seleccionar (P) · Alt+clic: rechazar (X) · clic derecho: más opciones",
  "fr": "Clic : retenir (P) · Alt+clic : rejeter (X) · clic droit : autres options",
  "de": "Klick: auswählen (P) · Alt+Klick: ablehnen (X) · Rechtsklick: weitere Optionen",
  "pt": "Clique: escolher (P) · Alt+clique: rejeitar (X) · botão direito: mais opções",
  "ru": "Щелчок: отобрать (P) · Alt+щелчок: отклонить (X) · правый щелчок: другие действия",
  "ja": "クリック: 採用 (P) · Alt+クリック: 除外 (X) · 右クリック: その他のオプション",
  "ko": "클릭: 선택 (P) · Alt+클릭: 거부 (X) · 오른쪽 클릭: 기타 옵션",
  "zh": "单击：留用 (P) · Alt+单击：排除 (X) · 右键：更多选项"},
 "Clip Importer keeps running in the notification area and opens by itself when you insert a card.": {
  "it": "Clip Importer resta attivo nell'area di notifica e si apre da solo quando inserisci una scheda.",
  "es": "Clip Importer sigue funcionando en el área de notificación y se abre solo cuando insertas una tarjeta.",
  "fr": "Clip Importer reste actif dans la zone de notification et s'ouvre tout seul quand vous insérez une carte.",
  "de": "Clip Importer läuft im Infobereich weiter und öffnet sich von selbst, wenn du eine Karte einlegst.",
  "pt": "O Clip Importer continua ativo na área de notificação e abre sozinho quando você insere um cartão.",
  "ru": "Clip Importer продолжает работать в области уведомлений и откроется сам, когда вы вставите карту.",
  "ja": "Clip Importer は通知領域で動作し続け、カードを挿入すると自動で開きます。",
  "ko": "Clip Importer는 알림 영역에서 계속 실행되며 카드를 넣으면 자동으로 열립니다.",
  "zh": "Clip Importer 会继续在通知区域运行，插入存储卡时会自动打开。"},
 "Clip Importer opens by itself when you insert a card and shows you what to import. You can close this window: it keeps running in the notification area.": {
  "it": "Clip Importer si apre da solo quando colleghi la scheda e ti mostra le clip da importare. Puoi chiudere questa finestra: resta attivo nell'area di notifica.",
  "es": "Clip Importer se abre solo cuando insertas una tarjeta y te muestra qué importar. Puedes cerrar esta ventana: sigue funcionando en el área de notificación.",
  "fr": "Clip Importer s'ouvre tout seul quand vous insérez une carte et vous montre ce qu'il y a à importer. Vous pouvez fermer cette fenêtre : il reste actif dans la zone de notification.",
  "de": "Clip Importer öffnet sich von selbst, wenn du eine Karte einlegst, und zeigt dir, was importiert werden kann. Du kannst dieses Fenster schließen: Die App läuft im Infobereich weiter.",
  "pt": "O Clip Importer abre sozinho quando você insere um cartão e mostra o que importar. Você pode fechar esta janela: ele continua ativo na área de notificação.",
  "ru": "Clip Importer открывается сам, когда вы вставляете карту, и показывает, что можно импортировать. Это окно можно закрыть: программа продолжит работать в области уведомлений.",
  "ja": "カードを挿入すると Clip Importer が自動で開き、読み込む項目を表示します。このウインドウは閉じてもかまいません。通知領域で動作し続けます。",
  "ko": "카드를 넣으면 Clip Importer가 자동으로 열려 가져올 항목을 보여 줍니다. 이 창을 닫아도 알림 영역에서 계속 실행됩니다.",
  "zh": "插入存储卡时，Clip Importer 会自动打开并显示可导入的内容。你可以关闭此窗口：它会继续在通知区域运行。"},
 "Copies, verifies byte by byte, then deletes the originals {0} (Ctrl+Alt+I)": {
  "it": "Copia, verifica byte per byte e poi cancella gli originali {0} (Ctrl+Alt+I)",
  "es": "Copia, verifica byte a byte y luego elimina los originales {0} (Ctrl+Alt+I)",
  "fr": "Copie, vérifie octet par octet, puis supprime les originaux {0} (Ctrl+Alt+I)",
  "de": "Kopiert, prüft Byte für Byte und löscht dann die Originale {0} (Strg+Alt+I)",
  "pt": "Copia, verifica byte a byte e depois apaga os originais {0} (Ctrl+Alt+I)",
  "ru": "Копирует, побайтно проверяет и затем удаляет оригиналы {0} (Ctrl+Alt+I)",
  "ja": "コピーして 1 バイトずつ照合し、元のファイルを{0}削除します (Ctrl+Alt+I)",
  "ko": "복사한 뒤 바이트 단위로 확인하고 원본을 {0} 삭제합니다 (Ctrl+Alt+I)",
  "zh": "复制并逐字节校验，然后{0}删除原件 (Ctrl+Alt+I)"},
 "Move rejected to the Recycle Bin": {
  "it": "Sposta le scartate nel Cestino", "es": "Mover las rechazadas a la Papelera de reciclaje",
  "fr": "Placer les rejetées dans la Corbeille", "de": "Abgelehnte in den Papierkorb verschieben",
  "pt": "Mover as rejeitadas para a Lixeira", "ru": "Переместить отклонённые в Корзину",
  "ja": "除外した項目をごみ箱に移動", "ko": "거부한 항목을 휴지통으로 이동", "zh": "将排除的项目移到回收站"},
 "Move to the Recycle Bin": {
  "it": "Sposta nel Cestino", "es": "Mover a la Papelera de reciclaje", "fr": "Placer dans la Corbeille",
  "de": "In den Papierkorb verschieben", "pt": "Mover para a Lixeira", "ru": "Переместить в Корзину",
  "ja": "ごみ箱に移動", "ko": "휴지통으로 이동", "zh": "移到回收站"},
 "Originals go to the Recycle Bin only after verifying that the copy is identical": {
  "it": "Gli originali finiscono nel Cestino solo dopo aver verificato che la copia è identica",
  "es": "Los originales van a la Papelera de reciclaje solo después de verificar que la copia es idéntica",
  "fr": "Les originaux vont dans la Corbeille seulement après avoir vérifié que la copie est identique",
  "de": "Die Originale kommen erst in den Papierkorb, nachdem geprüft wurde, dass die Kopie identisch ist",
  "pt": "Os originais só vão para a Lixeira depois de verificar que a cópia é idêntica",
  "ru": "Оригиналы попадают в Корзину только после проверки, что копия идентична",
  "ja": "コピーが同一であることを確認してから、元のファイルをごみ箱に移動します",
  "ko": "복사본이 동일한지 확인한 후에만 원본을 휴지통으로 옮깁니다",
  "zh": "仅在确认副本完全相同后，才会将原件移到回收站"},
 "Picked: only picks get imported · click to remove · Alt+click to reject": {
  "it": "Scelta: si importano solo le scelte · clic per togliere · Alt+clic per scartare",
  "es": "Seleccionada: solo se importan las seleccionadas · clic para quitar · Alt+clic para rechazar",
  "fr": "Retenue : seules les retenues sont importées · clic pour retirer · Alt+clic pour rejeter",
  "de": "Ausgewählt: nur ausgewählte werden importiert · Klick zum Entfernen · Alt+Klick zum Ablehnen",
  "pt": "Escolhida: só as escolhidas são importadas · clique para tirar · Alt+clique para rejeitar",
  "ru": "Отобрано: импортируются только отобранные · щелчок — снять · Alt+щелчок — отклонить",
  "ja": "採用: 採用した項目だけが読み込まれます · クリックで解除 · Alt+クリックで除外",
  "ko": "선택됨: 선택한 항목만 가져옵니다 · 클릭하여 해제 · Alt+클릭하여 거부",
  "zh": "已留用：只导入留用的项目 · 单击取消 · Alt+单击排除"},
 "Re-read the folder (F5) · new clips show up automatically anyway": {
  "it": "Rileggi la cartella (F5) · le clip nuove compaiono comunque da sole",
  "es": "Volver a leer la carpeta (F5) · los clips nuevos aparecen solos de todos modos",
  "fr": "Relire le dossier (F5) · les nouveaux clips apparaissent de toute façon automatiquement",
  "de": "Ordner neu einlesen (F5) · neue Clips erscheinen ohnehin automatisch",
  "pt": "Ler a pasta de novo (F5) · os novos clipes aparecem sozinhos de qualquer forma",
  "ru": "Перечитать папку (F5) · новые клипы всё равно появляются автоматически",
  "ja": "フォルダを再読み込み (F5) · 新しいクリップはどのみち自動で表示されます",
  "ko": "폴더 다시 읽기 (F5) · 새 클립은 어차피 자동으로 표시됩니다",
  "zh": "重新读取文件夹 (F5) · 新片段本来也会自动显示"},
 "Show in File Explorer": {
  "it": "Mostra in Esplora file", "es": "Mostrar en el Explorador de archivos", "fr": "Afficher dans l'Explorateur de fichiers",
  "de": "Im Datei-Explorer anzeigen", "pt": "Mostrar no Explorador de Arquivos", "ru": "Показать в Проводнике",
  "ja": "エクスプローラーで表示", "ko": "파일 탐색기에서 보기", "zh": "在文件资源管理器中显示"},
 "Show in File Explorer when done": {
  "it": "Mostra in Esplora file al termine", "es": "Mostrar en el Explorador de archivos al terminar",
  "fr": "Afficher dans l'Explorateur de fichiers à la fin", "de": "Danach im Datei-Explorer anzeigen",
  "pt": "Mostrar no Explorador de Arquivos ao terminar", "ru": "Показать в Проводнике по завершении",
  "ja": "完了したらエクスプローラーで表示", "ko": "완료되면 파일 탐색기에서 보기", "zh": "完成后在文件资源管理器中显示"},
 "With nothing selected, imports everything new (Ctrl+I) · hold Alt to move": {
  "it": "Senza selezione importa tutto ciò che è nuovo (Ctrl+I) · tieni premuto Alt per spostare",
  "es": "Sin selección, importa todo lo nuevo (Ctrl+I) · mantén pulsada Alt para mover",
  "fr": "Sans sélection, importe tout ce qui est nouveau (Ctrl+I) · maintenez Alt pour déplacer",
  "de": "Ohne Auswahl wird alles Neue importiert (Strg+I) · Alt gedrückt halten zum Verschieben",
  "pt": "Sem seleção, importa tudo o que é novo (Ctrl+I) · segure Alt para mover",
  "ru": "Без выделения импортирует всё новое (Ctrl+I) · удерживайте Alt, чтобы переместить",
  "ja": "何も選択していなければ新しい項目をすべて読み込みます (Ctrl+I) · Alt キーを押したままで移動",
  "ko": "선택한 항목이 없으면 새 항목을 모두 가져옵니다 (Ctrl+I) · Alt 키를 누르고 있으면 이동",
  "zh": "未选择任何项目时导入所有新项目 (Ctrl+I) · 按住 Alt 可改为移动"},
 "{0} copied · paste them in File Explorer with Ctrl+V": {
  "it": "{0} negli appunti · incollale in Esplora file con Ctrl+V",
  "es": "{0} copiados · pégalos en el Explorador de archivos con Ctrl+V",
  "fr": "{0} copiés · collez-les dans l'Explorateur de fichiers avec Ctrl+V",
  "de": "{0} kopiert · im Datei-Explorer mit Strg+V einsetzen",
  "pt": "{0} copiados · cole no Explorador de Arquivos com Ctrl+V",
  "ru": "Скопировано: {0} · вставьте в Проводнике сочетанием Ctrl+V",
  "ja": "{0}をコピーしました · エクスプローラーで Ctrl+V で貼り付けられます",
  "ko": "{0} 복사됨 · 파일 탐색기에서 Ctrl+V로 붙여 넣으세요",
  "zh": "已复制 {0} · 在文件资源管理器中按 Ctrl+V 粘贴"},
 "{0} moved to the Recycle Bin": {
  "it": "{0} spostate nel Cestino", "es": "{0} movidos a la Papelera de reciclaje", "fr": "{0} placés dans la Corbeille",
  "de": "{0} in den Papierkorb verschoben", "pt": "{0} movidos para a Lixeira", "ru": "В Корзину перемещено: {0}",
  "ja": "{0}をごみ箱に移動しました", "ko": "{0}을(를) 휴지통으로 이동했습니다", "zh": "已将 {0} 移到回收站"},
}

LANGS = ["it", "es", "fr", "de", "pt", "ru", "ja", "ko", "zh"]
out = {
    "_readme": "Clip Importer for Windows: phrases that differ from the Mac app (File Explorer, Recycle Bin, Ctrl/Alt…). "
               "Same format as Resources/strings.json, which holds everything shared by both apps; entries here take precedence.",
    "translations": {lang: {k: T[k][lang] for k in sorted(T)} for lang in LANGS},
}
path = os.path.join(os.path.dirname(__file__), '..', 'strings.windows.json')
with open(path, 'w', encoding='utf-8') as f:
    json.dump(out, f, ensure_ascii=False, indent=2)
    f.write('\n')
print('wrote', os.path.abspath(path), len(T), 'keys ×', len(LANGS), 'languages')
