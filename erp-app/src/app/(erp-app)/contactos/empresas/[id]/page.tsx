import { notFound, redirect } from "next/navigation";
import { Volver } from "@/components/ui/Volver";
import { idSchema } from "@/lib/validacion";
import { puedeVerContactos } from "@/modules/contactos/permissions";
import { getFusionada } from "@/modules/contactos/queries";
import { fichaEmpresa } from "./ficha";

export default async function EmpresaPage(props: PageProps<"/contactos/empresas/[id]">) {
  const { id } = await props.params;
  if (!idSchema.safeParse(id).success) notFound();
  const ficha = await fichaEmpresa(id);
  if (ficha)
    return (
      <div className="flex flex-col gap-4">
        <Volver href="/contactos/empresas">Empresas</Volver>
        {ficha}
      </div>
    );
  const fusionada = (await puedeVerContactos()) ? await getFusionada("empresa", id) : null;
  if (fusionada?.id) redirect(`/contactos/empresas/${fusionada.id}`);
  notFound();
}
