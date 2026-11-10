import { notFound } from "next/navigation";
import { Volver } from "@/components/ui/Volver";
import { idSchema } from "@/lib/validacion";
import { puedeVerPresupuestos } from "@/modules/presupuestos/permissions";
import { getPresupuesto } from "@/modules/presupuestos/queries";
import { FichaPresupuestoView } from "@/modules/presupuestos/components/FichaPresupuestoView";

export default async function PresupuestoPage(props: PageProps<"/presupuestos/[id]">) {
  const { id } = await props.params;
  if (!idSchema.safeParse(id).success || !(await puedeVerPresupuestos())) notFound();
  const presupuesto = await getPresupuesto(id);
  if (!presupuesto) notFound();
  return (
    <div className="flex flex-col gap-4">
      <Volver href="/presupuestos">Presupuestos</Volver>
      <FichaPresupuestoView presupuesto={presupuesto} />
    </div>
  );
}
