import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { puedeAdministrar, puedeAprobar, puedeVerContactos } from "@/modules/contactos/permissions";
import { getEmpresas, getNombres, getPorAprobar } from "@/modules/contactos/queries";
import { ContactosView } from "@/modules/contactos/components/ContactosView";

export default async function EmpresasPage() {
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerContactos())) notFound();

  const todas = await puedeAdministrar();
  const [empresas, nombres] = await Promise.all([getEmpresas({ todas, yo }), getNombres()]);

  return (
    <ContactosView
      tipo="empresa"
      filas={empresas.map((e) => ({
        id: e.id,
        nombre: e.nombre,
        detalle:
          todas && e.equipo_id
            ? (nombres[e.equipo_id] ?? null)
            : e.compartida && e.equipo_id
              ? `Compartida por ${nombres[e.equipo_id] ?? "otro equipo"}`
              : null,
        activo: e.activo,
        congelada: e.congelada,
        huerfana: e.huerfana,
        responsable_id: null,
      }))}
      porAprobar={(await puedeAprobar()) ? (await getPorAprobar()).length : undefined}
      administrar={todas ? { de: null } : undefined}
    />
  );
}
