import QtQuick
import Qt.labs.folderlistmodel

// The lock clone's EmberLayer.qml (lock-embers.sh copies this file in under that name).
//
// The Omarchy shell keeps its lock service loaded for the whole session, and Qt reuses a QML type it has
// built, so a rewritten EmberLayer.qml would only show at the next login. The embers themselves live in
// Embers.qml next to this file (what `lock-embers.sh recolor` writes, replacing the file). Each time the
// lock screen or its preview shows (the LockView above turns loadBackground on), this loads Embers.qml
// under a URL that carries the file's modification time, so a theme or EMBER_STYLE change shows on the
// next lock. Qt builds each version once: an unchanged file gets the same URL and the copy Qt keeps.
// While hidden, nothing is loaded. Without a LockView above, it loads whenever the file is there.
Loader {
  readonly property Item view: {
    for (var p = parent; p; p = p.parent) if (p.loadBackground !== undefined) return p
    return null
  }

  FolderListModel { id: dir; folder: Qt.resolvedUrl("."); nameFilters: ["Embers.qml"]; showDirs: false }

  source: (!view || view.loadBackground) && dir.count
    ? Qt.resolvedUrl("Embers.qml") + "?v=" + dir.get(0, "fileModified").getTime() : ""
}
