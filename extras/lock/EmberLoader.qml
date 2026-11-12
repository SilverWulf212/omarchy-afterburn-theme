import QtQuick
import Qt.labs.folderlistmodel

// The lock clone's EmberLayer.qml (lock-embers.sh copies this file in under that name).
//
// The Omarchy shell keeps its lock service loaded for the whole session. Quickshell also keeps the text of every
// QML file it has loaded, by path, and Qt caches each folder's file list, so a file rewritten in place, or a new file
// in a folder already read, would only show at the next login. `lock-embers.sh recolor` therefore writes each set of
// embers into a new folder, embers.<n>/Embers.qml, and deletes the old one. Each time the lock screen or its preview
// shows (the LockView above turns loadBackground on), this loads the newest of those folders, so a theme or
// EMBER_STYLE change shows on the next lock. Showing again with nothing new reuses what Qt already built. While
// hidden, nothing is loaded. Without a LockView above, it loads whenever a folder is there.
Loader {
  readonly property Item view: {
    for (var p = parent; p; p = p.parent) if (p.loadBackground !== undefined) return p
    return null
  }

  // Folders only. nameFilters do not apply to folders, so the newest embers.<n> is picked by name below.
  FolderListModel {
    id: versions
    folder: Qt.resolvedUrl(".")
    showFiles: false
  }

  function newest() {
    for (var i = versions.count - 1; i >= 0; i--) {
      var name = versions.get(i, "fileName")
      if (name.startsWith("embers.")) return versions.folder + name + "/Embers.qml"
    }
    return ""
  }

  source: !view || view.loadBackground ? newest() : ""
}
