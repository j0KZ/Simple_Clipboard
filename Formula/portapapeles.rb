class Portapapeles < Formula
  desc "Historial del portapapeles estilo Win+V, para macOS"
  homepage "https://github.com/j0KZ/Simple_Clipboard"
  url "https://github.com/j0KZ/Simple_Clipboard/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  head "https://github.com/j0KZ/Simple_Clipboard.git", branch: "main"

  # El Info.plist declara LSMinimumSystemVersion 14.0.
  depends_on macos: :sonoma

  # Es una fórmula y no un cask a propósito: la app se compila en el equipo de quien la
  # instala. Una app precompilada y bajada de internet llega con el atributo de cuarentena,
  # y como no está notarizada (hace falta cuenta de desarrollador de pago) Gatekeeper la
  # rechaza. Compilándola aquí no hay cuarentena y arranca sin pelear con el sistema.
  def install
    # Dos cosas que SwiftPM hace y el sandbox de Homebrew no tolera:
    #   · cachear en $HOME  -> se le redirige todo dentro del directorio de compilación;
    #   · sandboxear él mismo el manifiesto -> sandbox-exec no anida, y falla con
    #     "sandbox_apply: Operation not permitted". Homebrew ya nos tiene aislados.
    ENV["SWIFT_BUILD_FLAGS"] = "--disable-sandbox " \
                               "--cache-path #{buildpath}/.spm/cache " \
                               "--config-path #{buildpath}/.spm/config " \
                               "--security-path #{buildpath}/.spm/security " \
                               "--scratch-path #{buildpath}/.build"

    system "./build.sh"
    prefix.install "build/Portapapeles.app"

    # `portapapeles` desde la terminal lanza la app.
    (bin/"portapapeles").write <<~SH
      #!/bin/bash
      exec open -a "#{opt_prefix}/Portapapeles.app" "$@"
    SH
    chmod 0755, bin/"portapapeles"
  end

  def caveats
    <<~EOS
      Para que aparezca en Launchpad y Spotlight:
        ln -sfn #{opt_prefix}/Portapapeles.app /Applications/Portapapeles.app

      Para lanzarla:
        portapapeles

      Vive en la barra de menús. El atajo es ⌥⌘V y se cambia en Preferencias.

      Para que pegue sola al elegir un recorte hay que concederle Accesibilidad en
      Ajustes → Privacidad y seguridad → Accesibilidad. Sin ese permiso igual funciona:
      copia el recorte y lo pegas tú con ⌘V.

      Ojo al actualizar: cada versión vive en una ruta distinta del Cellar, y macOS ata
      ese permiso a la ruta. Si después de un `brew upgrade` deja de pegar sola, quítala
      de esa lista con «−» y vuelve a agregarla.

      Para que arranque al iniciar sesión, actívalo en Preferencias → General.
    EOS
  end

  test do
    assert_predicate prefix/"Portapapeles.app/Contents/MacOS/Portapapeles", :executable?
    assert_match "com.j0kz.Portapapeles",
                 (prefix/"Portapapeles.app/Contents/Info.plist").read
  end
end
