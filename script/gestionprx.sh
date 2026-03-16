#!/bin/bash

# ============================================================
#  Script para gestionar usuarios en Proxmox
#  - Crea usuarios con su carpeta (pool) privada
#  - Borra usuarios junto con todo su contenido
# ============================================================

# Contraseña que se le pone a todos los usuarios nuevos (mínimo 8 caracteres)
PASSWORD_GENERICA="Fcp2024!"

# Nombre del rol con los permisos que tendrá cada usuario
ROL_PROPIO="Propio"

# Espacios de almacenamiento a los que tendrá acceso el usuario
STORAGES=("local" "local-lvm")

# Zona SDN a la que tendrán acceso los usuarios
SDN_ZONA="localred"

# -------------------------------------------------------
# Comprobaciones iniciales antes de arrancar el script
# -------------------------------------------------------
comprobaciones_iniciales(){
   # Comprobar que se ejecuta como root
   if [ "$EUID" -ne 0 ]; then
      echo "ERROR: Este script debe ejecutarse como root."
      exit 1
   fi

   # Comprobar que el rol "Propio" existe en Proxmox
   if ! pvesh get /access/roles --output-format yaml | grep -q "roleid: $ROL_PROPIO"; then
      echo "ERROR: El rol '$ROL_PROPIO' no existe en Proxmox. Créalo antes de usar este script."
      exit 1
   fi
}

# -------------------------------------------------------
# Comprobar que el nombre de usuario es válido
# Solo letras, números y guiones, sin espacios ni símbolos
# -------------------------------------------------------
nombre_valido(){
   if [[ ! "$1" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo "    AVISO: El nombre '$1' no es válido. Solo se permiten letras, números, guiones y guiones bajos."
      return 1
   fi
   return 0
}

# -------------------------------------------------------
# Opción 1 - Crear usuarios
# -------------------------------------------------------
agregar(){
   echo ""
   read -p "Introduce los usuarios separados por espacio (ej: usuario1 usuario2): " profesorado

   for i in ${profesorado[@]}; do

      echo ""
      echo ">>> Procesando usuario: $i"

      # Comprobar que el nombre de usuario es válido
      if ! nombre_valido "$i"; then
         continue
      fi

      # Comprobar si el usuario ya existe
      if pvesh get /access/users --output-format yaml | grep -q "^$i@pve:"; then
         read -p "    El usuario '$i' ya existe. ¿Quieres continuar igualmente? (s/n): " respuesta
         if [[ "$respuesta" != "s" ]]; then
            echo "    Saltando usuario $i..."
            continue
         fi
      fi

      # Comprobar si el pool ya existe
      if pvesh get /pools --output-format yaml | grep -q "poolid: pool_$i"; then
         read -p "    El pool 'pool_$i' ya existe. ¿Quieres continuar igualmente? (s/n): " respuesta
         if [[ "$respuesta" != "s" ]]; then
            echo "    Saltando usuario $i..."
            continue
         fi
      fi

      # Crear el usuario y ponerle la contraseña genérica
      pveum useradd "$i@pve" --comment "Usuario creado automáticamente"
      pvesh set /access/password --userid "$i@pve" --password "$PASSWORD_GENERICA"

      # Crear la carpeta privada (pool) del usuario
      pvesh create /pools -poolid "pool_$i" -comment "Pool privado de $i"

      # Dar al usuario permisos sobre su propia carpeta
      pvesh set /access/acl \
         -path "/pool/pool_$i" \
         -roles "$ROL_PROPIO" \
         -users "$i@pve" \
         -propagate 1

      # Dar acceso a la zona SDN y sus redes virtuales (propagate 1 para heredar a las VNets)
      pvesh set /access/acl \
         -path "/sdn/zones/$SDN_ZONA" \
         -roles "$ROL_PROPIO" \
         -users "$i@pve" \
         -propagate 1

      # Añadir los almacenamientos a su carpeta y darle acceso a ellos
      for storage in "${STORAGES[@]}"; do
         pvesh set /pools/"pool_$i" -storage "$storage"
         pvesh set /access/acl \
            -path "/storage/$storage" \
            -roles "$ROL_PROPIO" \
            -users "$i@pve" \
            -propagate 0
      done

      echo "    Usuario $i creado correctamente."
      echo "    Carpeta: pool_$i | Contraseña: $PASSWORD_GENERICA"
   done
}

# -------------------------------------------------------
# Opción 2 - Borrar usuarios (elimina todo lo suyo)
# -------------------------------------------------------
eliminar(){
   echo ""
   read -p "Introduce los usuarios a eliminar separados por espacio (ej: usuario1 usuario2): " profesorado

   for i in ${profesorado[@]}; do

      echo ""
      echo ">>> Procesando usuario: $i"

      # Comprobar si el usuario existe antes de intentar borrarlo
      if ! pvesh get /access/users --output-format yaml | grep -q "^$i@pve:"; then
         echo "    AVISO: El usuario '$i' no existe, saltando..."
         continue
      fi

      # Comprobar si el pool existe antes de intentar borrarlo
      if ! pvesh get /pools --output-format yaml | grep -q "poolid: pool_$i"; then
         echo "    AVISO: El pool 'pool_$i' no existe, saltando limpieza del pool..."
      fi

      # Pedir confirmación antes de borrar todo
      read -p "    ¿Seguro que quieres borrar al usuario '$i' y todo su contenido? (s/n): " respuesta
      if [[ "$respuesta" != "s" ]]; then
         echo "    Cancelado para $i."
         continue
      fi

      # Sacar la lista de IDs de máquinas que hay en su carpeta
      echo "    Buscando sus máquinas virtuales..."
      pvesh get /pools/"pool_$i" --output-format yaml | grep -w vmid | awk '{print $2}' > /tmp/vms_$i.txt

      if [ -s /tmp/vms_$i.txt ]; then
         while read vmid; do
            echo "    Borrando máquina $vmid..."
            # Apagarla primero por si está encendida
            qm stop "$vmid" 2>/dev/null || pct stop "$vmid" 2>/dev/null
            sleep 2
            # Borrarla completamente
            qm destroy "$vmid" --purge 2>/dev/null || pct destroy "$vmid" --purge 2>/dev/null
         done < /tmp/vms_$i.txt
      else
         echo "    No tiene máquinas, continuando..."
      fi

      # Borrar el archivo temporal
      rm -f /tmp/vms_$i.txt

      # Quitarle el acceso a los almacenamientos
      for storage in "${STORAGES[@]}"; do
         pvesh set /access/acl \
            -path "/storage/$storage" \
            -roles "$ROL_PROPIO" \
            -users "$i@pve" \
            -delete 1 2>/dev/null
      done

      # Quitarle el acceso a la zona SDN
      pvesh set /access/acl \
         -path "/sdn/zones/$SDN_ZONA" \
         -roles "$ROL_PROPIO" \
         -users "$i@pve" \
         -delete 1 2>/dev/null

      # Quitarle el acceso a su carpeta
      pvesh set /access/acl \
         -path "/pool/pool_$i" \
         -roles "$ROL_PROPIO" \
         -users "$i@pve" \
         -delete 1 2>/dev/null

      # Desvincular los almacenamientos de su carpeta antes de borrarla
      for storage in "${STORAGES[@]}"; do
         pvesh set /pools/"pool_$i" -storage "$storage" -delete 1 2>/dev/null
      done

      # Borrar la carpeta del usuario
      pvesh delete /pools/"pool_$i" 2>/dev/null
      echo "    Carpeta pool_$i eliminada."

      # Borrar la cuenta del usuario
      pveum userdel "$i@pve"
      echo "    Usuario $i@pve eliminado."

      echo "    $i borrado completamente."
   done
}

# -------------------------------------------------------
# MENÚ PRINCIPAL
# -------------------------------------------------------
comprobaciones_iniciales

op=1
while [ $op -ne 0 ]; do
   echo ""
   echo "============================================"
   echo "  Gestión de usuarios Proxmox"
   echo "============================================"
   echo "  0 - Salir"
   echo "  1 - Agregar usuarios"
   echo "  2 - Eliminar usuarios (borra todo su contenido)"
   echo "============================================"
   read -p "Selecciona una opción: " op

   case $op in
      1) agregar ;;
      2) eliminar ;;
      0) echo "Saliendo..."; break ;;
      *) echo "Opción no válida." ;;
   esac
done