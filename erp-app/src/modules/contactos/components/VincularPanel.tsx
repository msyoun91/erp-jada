"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearYVincular, vincular } from "../actions";
import { crearYVincularSchema, type CrearYVincularForm, type Vinculable } from "../types";
import { BuscadorVinculables, EmpresaSelector, type EmpresaElegida, type TipoContacto } from "./Buscador";
import { AvisoParecidas, useParecidas } from "./Parecidas";
import { RolesCheck } from "./RolesCheck";

const FORM_ID = "crear-y-vincular";

// Buscar o crear en el mismo panel (`decisiones/contactos.md` → *Vincular*):
// elegir un resultado vincula; si no está, se crea y se vincula en un paso.
export function VincularPanel({
  ente,
  registroId,
  rolInicial,
  empresasDelRegistro,
  onClose,
}: {
  ente: string;
  registroId: string;
  rolInicial: string | null;
  empresasDelRegistro: { id: string; nombre: string }[];
  onClose: () => void;
}) {
  const [roles, setRoles] = useState<string[]>(rolInicial ? [rolInicial] : []);
  const [creando, setCreando] = useState<{ tipo: TipoContacto; nombre: string } | null>(null);
  const [enviando, setEnviando] = useState(false);

  async function elegir(v: Vinculable) {
    if (enviando) return;
    if (roles.length === 0) {
      toast.error("Elegí al menos un rol");
      return;
    }
    setEnviando(true);
    const result = await vincular({
      ente,
      registro_id: registroId,
      roles,
      persona_id: v.tipo === "persona" ? v.id : null,
      empresa_id: v.tipo === "empresa" ? v.id : null,
    });
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(`${v.nombre} vinculado`);
    onClose();
  }

  return (
    <RightPanel
      title="Vincular contacto"
      onClose={onClose}
      hayCambios={creando !== null}
      footer={
        creando && (
          <>
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setCreando(null)} disabled={enviando}>
              Volver a buscar
            </button>
            <div className="flex-1" />
            <button type="submit" form={FORM_ID} className="btn btn-primary btn-sm" disabled={enviando}>
              {enviando ? "Guardando…" : "Crear y vincular"}
            </button>
          </>
        )
      }
    >
      <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4">
        <RolesCheck ente={ente} valor={roles} onCambio={setRoles} />
        {creando ? (
          <CrearForm
            key={creando.tipo}
            ente={ente}
            registroId={registroId}
            tipo={creando.tipo}
            nombre={creando.nombre}
            roles={roles}
            empresasDelRegistro={empresasDelRegistro}
            setEnviando={setEnviando}
            onUsar={(p) => elegir({ tipo: creando.tipo, id: p.id, nombre: p.nombre, detalle: "" })}
            onListo={onClose}
          />
        ) : (
          <BuscadorVinculables onElegir={elegir} onCrear={(tipo, nombre) => setCreando({ tipo, nombre })} />
        )}
      </div>
    </RightPanel>
  );
}

function CrearForm({
  ente,
  registroId,
  tipo,
  nombre,
  roles,
  empresasDelRegistro,
  setEnviando,
  onUsar,
  onListo,
}: {
  ente: string;
  registroId: string;
  tipo: TipoContacto;
  nombre: string;
  roles: string[];
  empresasDelRegistro: { id: string; nombre: string }[];
  setEnviando: (v: boolean) => void;
  onUsar: (p: { id: string; nombre: string }) => void;
  onListo: () => void;
}) {
  const [empresa, setEmpresa] = useState<EmpresaElegida | null>(null);
  const { parecidas, revisar } = useParecidas();
  const empresaNueva = useParecidas();
  const { register, handleSubmit, setValue, formState } = useForm<CrearYVincularForm>({
    resolver: zodResolver(crearYVincularSchema),
    defaultValues: { ente, registro_id: registroId, roles, tipo, nombre, telefono: "", email: "", cargo: "" },
  });
  const { errors } = formState;

  async function onSubmit(data: CrearYVincularForm) {
    setEnviando(true);
    const [contactoOk, empresaOk] = await Promise.all([
      revisar({ tipo: data.tipo, nombre: data.nombre, telefono: data.telefono, email: data.email }),
      data.empresa_nombre ? empresaNueva.revisar({ tipo: "empresa", nombre: data.empresa_nombre }) : true,
    ]);
    if (!contactoOk || !empresaOk) {
      setEnviando(false);
      return;
    }
    const result = await crearYVincular(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    const empresaEspera = data.empresa_nombre && empresaNueva.parecidas ? `; ${data.empresa_nombre} espera aprobación` : "";
    toast.success(parecidas ? `${data.nombre} creado: espera aprobación${empresaEspera}` : `${data.nombre} creado y vinculado${empresaEspera}`);
    onListo();
  }

  return (
    <form
      id={FORM_ID}
      onSubmit={(e) => {
        setValue("roles", roles);
        setValue("empresa_id", empresa?.id ?? null);
        setValue("empresa_nombre", empresa && empresa.id === null ? empresa.nombre : null);
        if (!empresa) setValue("cargo", "");
        return handleSubmit(onSubmit)(e);
      }}
      className="flex flex-col gap-4"
    >
      <p className="t-label">{tipo === "persona" ? "Persona nueva" : "Empresa nueva"}</p>
      {errors.roles && <p className="input-error-text">{errors.roles.message}</p>}
      <Campo id="cv-nombre" label="Nombre" requerido error={errors.nombre}>
        <input id="cv-nombre" aria-required className={claseInput(errors.nombre)} {...register("nombre")} />
      </Campo>
      <Campo id="cv-telefono" label="Teléfono" error={errors.telefono}>
        <input id="cv-telefono" type="tel" className={claseInput(errors.telefono)} {...register("telefono")} />
      </Campo>
      <Campo id="cv-email" label="Email" error={errors.email}>
        <input id="cv-email" type="email" className={claseInput(errors.email)} {...register("email")} />
      </Campo>
      {tipo === "persona" && (
        <>
          <div>
            <p className="t-label mb-1">Empresa</p>
            <EmpresaSelector valor={empresa} onCambio={setEmpresa} sugeridas={empresasDelRegistro} crear />
          </div>
          {empresa && (
            <Campo id="cv-cargo" label="Cargo" error={errors.cargo}>
              <input id="cv-cargo" placeholder="Capataz, compras…" className={claseInput(errors.cargo)} {...register("cargo")} />
            </Campo>
          )}
          {empresa?.id === null && empresaNueva.parecidas && (
            <AvisoParecidas
              tipo="empresa"
              items={empresaNueva.parecidas}
              verbo="creala"
              usar="Usar esa"
              onUsar={(p) => setEmpresa({ id: p.id, nombre: p.nombre })}
            />
          )}
        </>
      )}
      {parecidas && <AvisoParecidas tipo={tipo} items={parecidas} verbo="crealo" onUsar={onUsar} />}
    </form>
  );
}
