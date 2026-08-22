// Abre o cierra Preferencias en una instancia lanzada con CLIP_DEBUG=1.
// Compañero de TogglePanel.swift, para probar el ciclo de la ventana sin clics.
//
//   CLIP_DEBUG=1 ./build/Portapapeles.app/Contents/MacOS/Portapapeles &
//   swift tools/ToggleSettings.swift
import Foundation

DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.j0kz.Portapapeles.debugSettings"),
    object: nil,
    userInfo: nil,
    deliverImmediately: true
)
