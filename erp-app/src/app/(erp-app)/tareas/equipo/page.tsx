import { notFound } from "next/navigation";
import { puedeAdministrar, puedePedir, puedeVerEquipo } from "@/modules/tareas/permissions";
import { getAsignables, getContexto, getEquipo } from "@/modules/tareas/queries";
import { EquipoView } from "@/modules/tareas/components/EquipoView";

export default async function EquipoPage() {
  if (!(await puedeVerEquipo())) notFound();

  const [contexto, asignables, admin, pedir] = await Promise.all([
    getContexto(),
    getAsignables(),
    puedeAdministrar(),
    puedePedir(),
  ]);
  if (!contexto.miEquipo) notFound();
  const datos = await getEquipo(contexto.miEquipo);

  return <EquipoView {...datos} ctx={{ ...contexto, asignables, admin, pedir, delegador: true }} />;
}
