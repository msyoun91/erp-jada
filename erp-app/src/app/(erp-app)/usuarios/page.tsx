import { notFound, redirect } from "next/navigation";
import {
  puedeGestionarUsuarios,
  puedeVerEquipos,
  puedeVerMiEquipo,
  puedeVerUsuarios,
} from "@/modules/usuarios/permissions";
import { getAsignaciones, getSubmoduloReglas, getSubmodulos, getUsuarios } from "@/modules/usuarios/queries";
import { UsuariosView } from "@/modules/usuarios/components/UsuariosView";

export default async function UsuariosPage() {
  // El sidebar apunta acá: quien tiene otra vista del módulo va a la suya.
  if (!(await puedeVerUsuarios())) {
    if (await puedeVerEquipos()) redirect("/usuarios/equipos");
    if (await puedeVerMiEquipo()) redirect("/usuarios/mi-equipo");
    notFound();
  }

  const [usuarios, submodulos, reglas, asignaciones, puedeGestionar] = await Promise.all([
    getUsuarios(),
    getSubmodulos(),
    getSubmoduloReglas(),
    getAsignaciones(),
    puedeGestionarUsuarios(),
  ]);

  return (
    <UsuariosView
      usuarios={usuarios}
      submodulos={submodulos}
      reglas={reglas}
      asignaciones={asignaciones}
      puedeGestionar={puedeGestionar}
    />
  );
}
