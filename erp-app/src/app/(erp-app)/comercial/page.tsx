import { notFound } from "next/navigation";
import {
  puedeGestionarAjenos,
  puedeGestionarObras,
  puedeGestionarProspectos,
  puedeVerComision,
  puedeVerProspectos,
} from "@/modules/comercial/permissions";
import {
  getEmpresas,
  getFuentes,
  getObras,
  getPersonas,
  getProspectos,
  getUsuarioActualId,
  getUsuariosActivos,
} from "@/modules/comercial/queries";
import { ProspectosView } from "@/modules/comercial/components/ProspectosView";

export default async function ProspectosPage() {
  if (!(await puedeVerProspectos())) notFound();

  const [
    prospectos,
    obras,
    empresas,
    personas,
    fuentes,
    usuarios,
    usuarioActualId,
    gestionar,
    ajenos,
    gestionarObras,
    verComision,
  ] = await Promise.all([
    getProspectos(),
    getObras(),
    getEmpresas(),
    getPersonas(),
    getFuentes(),
    getUsuariosActivos(),
    getUsuarioActualId(),
    puedeGestionarProspectos(),
    puedeGestionarAjenos(),
    puedeGestionarObras(),
    puedeVerComision(),
  ]);

  return (
    <ProspectosView
      prospectos={prospectos}
      obras={obras}
      empresas={empresas}
      personas={personas}
      fuentes={fuentes}
      usuarios={usuarios}
      usuarioActualId={usuarioActualId}
      puedeGestionar={gestionar}
      gestionarAjenos={ajenos}
      gestionarObras={gestionarObras}
      verComision={verComision}
    />
  );
}
