import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { idSchema } from "@/lib/validacion";
import { desactivaEmpresa, puedeAdministrar, puedeVerContactos } from "@/modules/contactos/permissions";
import { getEmpresa, getNombres } from "@/modules/contactos/queries";
import { EmpresaView } from "@/modules/contactos/components/EmpresaView";

export default async function EmpresaPage(props: PageProps<"/contactos/empresas/[id]">) {
  const { id } = await props.params;
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerContactos()) || !idSchema.safeParse(id).success) notFound();

  const [datos, admin, nombres] = await Promise.all([getEmpresa(id), puedeAdministrar(), getNombres()]);
  if (!datos) notFound();

  return (
    <EmpresaView
      {...datos}
      yo={yo}
      admin={admin}
      desactiva={await desactivaEmpresa(datos.empresa, yo)}
      nombres={nombres}
    />
  );
}
