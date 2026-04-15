' ============================================================
'  Montar \\192.168.1.200\recursos al iniciar sesion
'  Coloca este archivo en shell:startup
' ============================================================

Dim servidor, letra
servidor = "\\192.168.1.200\recursos"
letra    = "Z:"

' Ejecutar net use en silencio (sin ventana)
Dim shell
Set shell = CreateObject("WScript.Shell")

' Desmontar por si ya estaba montada
shell.Run "cmd /c net use " & letra & " /delete /yes", 0, True

' Montar la unidad (sin credenciales)
shell.Run "cmd /c net use " & letra & " " & servidor & " /persistent:no", 0, True

' --- Si necesitas usuario y contraseña, comenta la linea anterior
'     y descomenta esta:
' shell.Run "cmd /c net use " & letra & " " & servidor & " /user:USUARIO CONTRASEÑA /persistent:no", 0, True

Set shell = Nothing