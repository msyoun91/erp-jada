import { notFound } from "next/navigation";
import { Volver } from "@/components/ui/Volver";
import { getUsuarioActualId } from "@/lib/usuarios";
import { idSchema } from "@/lib/validacion";
import { puedeVerPresupuestos } from "@/modules/presupuestos/permissions";
import { getNombres, getVersion } from "@/modules/presupuestos/queries";
import { VersionView } from "@/modules/presupuestos/components/VersionView";

export default async function VersionPage(props: PageProps<"/presupuestos/[id]/[version]">) {
  const { id, version } = await props.params;
  if (!idSchema.safeParse(id).success || !idSchema.safeParse(version).success) notFound();
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerPresupuestos())) notFound();
  const datos = await getVersion(id, version);
  if (!datos) notFound();
  // Quién pidió y quién resolvió; solo hacen falta con *Antes de publicar*.
  const nombres = datos.antes ? await getNombres() : {};
  return (
    <div className="flex flex-col gap-4">
      <Volver href={`/presupuestos/${id}`}>{datos.presupuesto.codigo}</Volver>
      <VersionView datos={datos} nombres={nombres} yo={yo} />
    </div>
  );
}
