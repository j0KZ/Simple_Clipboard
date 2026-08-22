// Abre o cierra el panel de una instancia lanzada con CLIP_DEBUG=1.
// Sirve para mirar la UI sin depender del atajo global ni de permisos de automatización.
//
//   CLIP_DEBUG=1 ./build/Portapapeles.app/Contents/MacOS/Portapapeles &
//   swift tools/TogglePanel.swift
import Foundation

DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.j0kz.Portapapeles.debugToggle"),
    object: nil,
    userInfo: nil,
    deliverImmediately: true
)
