import { notFound } from "next/navigation";
import { Volver } from "@/components/ui/Volver";
import { idSchema } from "@/lib/validacion";
import { puedeVerPaquetes } from "@/modules/catalogo/permissions";
import { puedeAutorizarTecnica, puedeRevisar } from "@/modules/presupuestos/permissions";
import { getRevisionVersion } from "@/modules/presupuestos/queries";
import { RevisionVersionView } from "@/modules/presupuestos/components/RevisionVersionView";

// *Ver despiece* lleva a Catálogo: se compone acá, con su permiso.
export default async function RevisionVersionPage(props: PageProps<"/presupuestos/revision/[version]">) {
  const { version } = await props.params;
  if (!idSchema.safeParse(version).success || !(await puedeRevisar())) notFound();
  const [datos, autoriza, despiece] = await Promise.all([
    getRevisionVersion(version),
    puedeAutorizarTecnica(),
    puedeVerPaquetes(),
  ]);
  if (!datos) notFound();
  return (
    <div className="flex flex-col gap-4">
      <Volver href="/presupuestos/revision">Revisión técnica</Volver>
      <RevisionVersionView datos={datos} autoriza={autoriza} despiece={despiece} />
    </div>
  );
}
