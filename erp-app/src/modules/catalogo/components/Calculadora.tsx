"use client";

import { useState, useTransition } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { EntradaCampos } from "@/components/entrada/EntradaCampos";
import { Campo, claseInput } from "@/components/ui/Campo";
import { FormModal } from "@/components/ui/FormModal";
import {
  aEntrada,
  desdeEntrada,
  ESTADO_VACIO,
  hayMalEscrita,
  type EntradaEstado,
  type FormularioEntrada,
} from "@/lib/entrada";
import { MONEDAS, MONEDAS_LISTA, type Moneda } from "@/lib/monedas";
import { calcular, guardarCaso } from "../actions";
import {
  casoSchema,
  type Caso,
  type CasoForm,
  type ColorVersion,
  type Contenido,
  type Despiece,
  type Entrada,
  type PrecioDetalle,
} from "../types";
import { DespieceResultado } from "./DespieceResultado";

const VENTANA = "ventana";

// Lo que cargaría un vendedor, para ver el despiece (y con `catalogo_aprobar`, el precio) de cualquier
// versión. No guarda nada: los casos de prueba se cargan en el editor.
export function Calculadora({
  versionId,
  contenido,
  colores,
  nombreInsumo,
  inicial,
  puedeAprobar,
  monedaPrincipal,
  comparar,
  guardaCasos,
}: {
  versionId: string;
  contenido: Contenido;
  colores: ColorVersion[];
  nombreInsumo: Map<string, string>;
  // `ventana`: lo cargado en la ventana de un presupuesto, desde Revisión técnica; se vuelve a elegir como un caso más.
  inicial: { caso: Caso | null; ventana: Entrada | null; resultado: Despiece | null; comparado: PrecioDetalle | null };
  puedeAprobar: boolean;
  monedaPrincipal: Moneda;
  comparar: { id: string; numero: number } | null;
  // Técnica, en un borrador: lo cargado se guarda como caso de prueba de la versión.
  guardaCasos: boolean;
}) {
  const inicio = inicial.ventana ?? inicial.caso?.entrada;
  const [estado, setEstado] = useState<EntradaEstado>(inicio ? desdeEntrada(inicio, contenido) : ESTADO_VACIO);
  const [casoId, setCasoId] = useState(inicial.ventana ? VENTANA : (inicial.caso?.id ?? ""));
  const [resultado, setResultado] = useState(inicial.resultado);
  const [comparado, setComparado] = useState(inicial.comparado);
  const [moneda, setMoneda] = useState<Moneda>(monedaPrincipal);
  const [opcionales, setOpcionales] = useState<string[]>([]);
  const [pendiente, startTransition] = useTransition();
  const [guardandoCaso, setGuardandoCaso] = useState(false);

  function correr(e: EntradaEstado, m = moneda, o = opcionales) {
    startTransition(async () => {
      const r = await calcular({
        version_id: versionId,
        entrada: aEntrada(e, contenido),
        precio: puedeAprobar ? { moneda: m, opcionales: o, comparar_con: comparar?.id ?? null } : null,
      });
      if (!r.success) {
        toast.error(r.error);
        return;
      }
      setResultado(r.resultado);
      setComparado(r.comparado);
    });
  }

  function elegirCaso(id: string) {
    setCasoId(id);
    const entrada = id === VENTANA ? inicial.ventana : contenido.casos.find((c) => c.id === id)?.entrada;
    const e = entrada ? desdeEntrada(entrada, contenido) : ESTADO_VACIO;
    setEstado(e);
    correr(e);
  }

  // El mismo formulario que el renglón de un presupuesto; acá el predeterminado de una variable es su fórmula.
  const formulario: FormularioEntrada = {
    piezas: contenido.piezas,
    variables: contenido.variables
      .filter((v) => v.ingresa_vendedor)
      .map((v) => ({ ...v, predeterminado: v.es_lista ? v.valor_predeterminado : v.formula })),
    materiales: contenido.materiales,
    opciones: contenido.opciones.map((o) => ({ ...o, nombre: nombreInsumo.get(o.insumo_id ?? "") ?? "" })),
    colores: colores.map((c) => ({ id: c.color_id, nombre: c.nombre, base: c.base, piezas_fuera: [], opciones_fuera: [] })),
  };
  const malEscrita = hayMalEscrita(contenido, estado);
  const serviciosOpcionales =
    resultado && "servicios" in resultado ? (resultado as PrecioDetalle).servicios.filter((s) => s.opcional) : [];

  return (
    <div className="grid gap-6 lg:grid-cols-[minmax(0,320px)_1fr]">
      <form
        className="flex flex-col gap-3"
        onSubmit={(e) => {
          e.preventDefault();
          correr(estado);
        }}
      >
        {(contenido.casos.length > 0 || inicial.ventana) && (
          <label className="flex flex-col gap-1">
            <span className="t-label">Caso de prueba</span>
            <select className="input" value={casoId} onChange={(e) => elegirCaso(e.target.value)}>
              {inicial.ventana && <option value={VENTANA}>Lo cargado en la ventana</option>}
              <option value="">Ninguno: todo predeterminado</option>
              {contenido.casos.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nombre}
                </option>
              ))}
            </select>
          </label>
        )}

        <EntradaCampos key={versionId} formulario={formulario} estado={estado} onChange={setEstado} />

        {puedeAprobar && (
          <>
            <label className="flex flex-col gap-1">
              <span className="t-label">Moneda del precio</span>
              <select className="input" value={moneda} onChange={(e) => setMoneda(e.target.value as Moneda)}>
                {MONEDAS_LISTA.map((x) => (
                  <option key={x} value={x}>
                    {MONEDAS[x]}
                  </option>
                ))}
              </select>
            </label>
            {serviciosOpcionales.map((s) => (
              <label key={s.porcentaje_id} className="tap-target flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={opcionales.includes(s.porcentaje_id)}
                  onChange={(e) =>
                    setOpcionales((o) =>
                      e.target.checked ? [...o, s.porcentaje_id] : o.filter((x) => x !== s.porcentaje_id),
                    )
                  }
                />
                <span className="t-body-m">{s.nombre} (opcional)</span>
              </label>
            ))}
          </>
        )}

        <button type="submit" className="btn btn-primary" disabled={pendiente || malEscrita}>
          {pendiente ? "Calculando…" : "Calcular"}
        </button>
        {guardaCasos && (
          <button
            type="button"
            className="btn btn-secondary"
            disabled={malEscrita}
            onClick={() => setGuardandoCaso(true)}
          >
            Guardar como caso
          </button>
        )}
      </form>
      {guardandoCaso && (
        <GuardarCasoModal
          versionId={versionId}
          entrada={aEntrada(estado, contenido)}
          onClose={() => setGuardandoCaso(false)}
        />
      )}

      <div className={pendiente ? "opacity-60" : ""}>
        {resultado ? (
          <DespieceResultado resultado={resultado} comparado={comparado} numeroComparado={comparar?.numero ?? null} />
        ) : (
          <p className="t-body-m">Cargá las medidas y tocá Calcular.</p>
        )}
      </div>
    </div>
  );
}

function GuardarCasoModal({
  versionId,
  entrada,
  onClose,
}: {
  versionId: string;
  entrada: Entrada;
  onClose: () => void;
}) {
  const { register, handleSubmit, formState } = useForm<CasoForm>({
    resolver: zodResolver(casoSchema),
    defaultValues: { version_id: versionId, nombre: "", entrada },
  });
  const { errors, isSubmitting } = formState;

  return (
    <FormModal
      title="Guardar como caso de prueba"
      confirmLabel="Guardar"
      onClose={onClose}
      enviando={isSubmitting}
      onSubmit={handleSubmit(async (d) => {
        const r = await guardarCaso(d);
        if (!r.success) {
          toast.error(r.error);
          return;
        }
        toast.success(`Se guardó el caso ${d.nombre}`);
        onClose();
      })}
    >
      <p className="t-body-m">
        Lo que está cargado, tal cual: lo vacío toma su predeterminado al calcular. El gerente revisa con estos casos, y
        la versión no se envía si alguno no se puede calcular.
      </p>
      <Campo id="caso-nombre" label="Nombre" requerido error={errors.nombre}>
        <input
          id="caso-nombre"
          aria-required
          placeholder="Chica 600 × 600"
          className={claseInput(errors.nombre)}
          {...register("nombre")}
        />
      </Campo>
    </FormModal>
  );
}
