import { getUsuarioActualId } from "@/lib/usuarios";
import { comparteEmpresa, desactivaEmpresa, puedeAdministrar, puedeVerContactos } from "@/modules/contactos/permissions";
import { getCompartida, getEmpresa, getFusionada, getNombres } from "@/modules/contactos/queries";
import { EmpresaView } from "@/modules/contactos/components/EmpresaView";

// La ficha de la empresa, en su página y en Tareas al lado del paso.
// Sin empresa visible, null.
export async function fichaEmpresa(id: string) {
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerContactos())) return null;

  const [datos, admin, nombres, compartida] = await Promise.all([
    getEmpresa(id),
    puedeAdministrar(),
    getNombres(),
    getCompartida(id),
  ]);
  if (!datos) return null;
  const fusionada = datos.empresa.fusionada_en ? await getFusionada("empresa", id) : null;

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
