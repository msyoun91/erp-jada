import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { puedeAdministrar, puedeAutorizar, puedeVerPresupuestos } from "@/modules/presupuestos/permissions";
import { getDevueltas, getEsperan, getNombres, getPresupuestos } from "@/modules/presupuestos/queries";
import { PresupuestosView } from "@/modules/presupuestos/components/PresupuestosView";

export default async function PresupuestosPage() {
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerPresupuestos())) notFound();

  const [autorizar, administrar] = await Promise.all([puedeAutorizar(), puedeAdministrar()]);
  const [presupuestos, devueltas, nombres, esperan] = await Promise.all([
    getPresupuestos(),
    getDevueltas(),
    getNombres(),
    autorizar || administrar ? getEsperan() : undefined,
  ]);

  return <PresupuestosView presupuestos={presupuestos} esperan={esperan} devueltas={devueltas} nombres={nombres} yo={yo} />;
}
