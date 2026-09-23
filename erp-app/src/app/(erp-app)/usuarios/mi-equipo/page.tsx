import { notFound } from "next/navigation";
import { puedeDelegar, puedeVerMiEquipo } from "@/modules/usuarios/permissions";
import { getMiEquipo, getSubmodulos } from "@/modules/usuarios/queries";
import { MiEquipoView } from "@/modules/usuarios/components/MiEquipoView";

export default async function MiEquipoPage() {
  if (!(await puedeVerMiEquipo())) notFound();

  const [miEquipo, submodulos, delegar] = await Promise.all([
    getMiEquipo(),
    getSubmodulos(),
    puedeDelegar(),
  ]);

  return <MiEquipoView miEquipo={miEquipo} submodulos={submodulos} puedeDelegar={delegar} />;
}
