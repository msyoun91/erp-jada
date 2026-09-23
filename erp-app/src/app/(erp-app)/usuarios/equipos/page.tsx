import { notFound } from "next/navigation";
import { puedeGestionarUsuarios, puedeVerEquipos } from "@/modules/usuarios/permissions";
import {
  getAsignaciones,
  getEquipos,
  getMembresias,
  getSubmodulos,
  getUsuarios,
} from "@/modules/usuarios/queries";
import { EquiposView } from "@/modules/usuarios/components/EquiposView";

export default async function EquiposPage() {
  if (!(await puedeVerEquipos())) notFound();

  const [equipos, membresias, usuarios, submodulos, asignaciones, puedeGestionar] =
    await Promise.all([
      getEquipos(),
      getMembresias(),
      getUsuarios(),
      getSubmodulos(),
      getAsignaciones(),
      puedeGestionarUsuarios(),
    ]);

  return (
    <EquiposView
      equipos={equipos}
      membresias={membresias}
      usuarios={usuarios}
      submodulos={submodulos}
      asignaciones={asignaciones}
      puedeGestionar={puedeGestionar}
    />
  );
}
