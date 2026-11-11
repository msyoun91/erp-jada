import { notFound } from "next/navigation";
import { Volver } from "@/components/ui/Volver";
import { idSchema } from "@/lib/validacion";
import { puedeVerPresupuestos } from "@/modules/presupuestos/permissions";
import { getVersion } from "@/modules/presupuestos/queries";
import { VersionView } from "@/modules/presupuestos/components/VersionView";

export default async function VersionPage(props: PageProps<"/presupuestos/[id]/[version]">) {
  const { id, version } = await props.params;
  if (!idSchema.safeParse(id).success || !idSchema.safeParse(version).success || !(await puedeVerPresupuestos())) notFound();
  const datos = await getVersion(id, version);
  if (!datos) notFound();
  return (
    <div className="flex flex-col gap-4">
      <Volver href={`/presupuestos/${id}`}>{datos.presupuesto.codigo}</Volver>
      <VersionView datos={datos} />
    </div>
  );
}
