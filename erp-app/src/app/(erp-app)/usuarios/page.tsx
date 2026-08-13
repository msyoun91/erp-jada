import { notFound } from "next/navigation";
import { puedeGestionarUsuarios, puedeVerUsuarios } from "@/modules/usuarios/permissions";
import { getAsignaciones, getSubmodulos, getUsuarios } from "@/modules/usuarios/queries";
import { UsuariosView } from "@/modules/usuarios/components/UsuariosView";

export default async function UsuariosPage() {
  if (!(await puedeVerUsuarios())) notFound();

  const [usuarios, submodulos, asignaciones, puedeGestionar] = await Promise.all([
    getUsuarios(),
    getSubmodulos(),
    getAsignaciones(),
    puedeGestionarUsuarios(),
  ]);

  return (
    <UsuariosView
      usuarios={usuarios}
      submodulos={submodulos}
      asignaciones={asignaciones}
      puedeGestionar={puedeGestionar}
    />
  );
}
