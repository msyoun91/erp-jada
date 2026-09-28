import { notFound, redirect } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { idSchema } from "@/lib/validacion";
import { comparteEmpresa, desactivaEmpresa, puedeAdministrar, puedeVerContactos } from "@/modules/contactos/permissions";
import { getCompartida, getEmpresa, getFusionada, getNombres } from "@/modules/contactos/queries";
import { EmpresaView } from "@/modules/contactos/components/EmpresaView";

export default async function EmpresaPage(props: PageProps<"/contactos/empresas/[id]">) {
  const { id } = await props.params;
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerContactos()) || !idSchema.safeParse(id).success) notFound();

  const [datos, admin, nombres, compartida] = await Promise.all([
    getEmpresa(id),
    puedeAdministrar(),
    getNombres(),
    getCompartida(id),
  ]);
  const fusionada = !datos || datos.empresa.fusionada_en ? await getFusionada("empresa", id) : null;
  if (!datos) {
    if (fusionada?.id) redirect(`/contactos/empresas/${fusionada.id}`);
    notFound();
  }

  return (
    <EmpresaView
      {...datos}
      yo={yo}
      admin={admin}
      desactiva={await desactivaEmpresa(datos.empresa, yo)}
      nombres={nombres}
      {...compartida}
      comparte={await comparteEmpresa(datos.empresa, yo)}
      fusionada={fusionada}
    />
  );
}
