import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { puedeAdministrar, puedeVerContactos } from "@/modules/contactos/permissions";
import { getCandidatos, getEmpresas, getNombres } from "@/modules/contactos/queries";
import { ContactosView } from "@/modules/contactos/components/ContactosView";

export default async function EmpresasPage() {
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerContactos())) notFound();

  const todas = await puedeAdministrar();
  const [empresas, nombres, candidatos] = await Promise.all([
    getEmpresas({ todas, yo }),
    getNombres(),
    todas ? getCandidatos() : [],
  ]);
  // Huérfana: activa, sin equipo y con una cargadora sin `contactos_ver`: no la
  // ve nadie más que el admin, que le asigna un equipo desde la ficha.
  const pueden = new Set(candidatos.map((c) => c.id));

  return (
    <ContactosView
      tipo="empresa"
      filas={empresas.map((e) => ({
        id: e.id,
        nombre: e.nombre,
        detalle: todas && e.equipo_id ? (nombres[e.equipo_id] ?? null) : null,
        activo: e.activo,
        huerfana: todas && e.activo && e.equipo_id === null && !pueden.has(e.creado_por),
        responsable_id: null,
      }))}
      administrar={todas ? { de: null } : undefined}
    />
  );
}
