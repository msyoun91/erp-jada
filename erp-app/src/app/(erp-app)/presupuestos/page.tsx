import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { puedeAdministrar, puedeArmar, puedeAutorizar, puedeVerPresupuestos } from "@/modules/presupuestos/permissions";
import { getDevueltas, getEsperan, getNombres, getObrasParaPresupuestar, getPresupuestos } from "@/modules/presupuestos/queries";
import { PresupuestosView } from "@/modules/presupuestos/components/PresupuestosView";

export default async function PresupuestosPage() {
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerPresupuestos())) notFound();

  const [autorizar, administrar, armar] = await Promise.all([puedeAutorizar(), puedeAdministrar(), puedeArmar()]);
  const [presupuestos, devueltas, nombres, esperan, obrasParaAlta] = await Promise.all([
    getPresupuestos(),
    getDevueltas(),
    getNombres(),
    autorizar || administrar ? getEsperan() : undefined,
    armar ? getObrasParaPresupuestar() : undefined,
  ]);

  return <PresupuestosView presupuestos={presupuestos} esperan={esperan} devueltas={devueltas} nombres={nombres} yo={yo} obrasParaAlta={obrasParaAlta} />;
}
