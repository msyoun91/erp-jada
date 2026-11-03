export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      catalogo_casos: {
        Row: {
          activo: boolean
          created_at: string
          entrada: Json
          id: string
          nombre: string
          updated_at: string
          version_id: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          entrada?: Json
          id?: string
          nombre: string
          updated_at?: string
          version_id: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          entrada?: Json
          id?: string
          nombre?: string
          updated_at?: string
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogo_casos_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_versiones"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogo_categorias: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          nombre: string
          tipo: Database["public"]["Enums"]["tipo_catalogo"]
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          nombre: string
          tipo: Database["public"]["Enums"]["tipo_catalogo"]
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          nombre?: string
          tipo?: Database["public"]["Enums"]["tipo_catalogo"]
          updated_at?: string
        }
        Relationships: []
      }
      catalogo_colores: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          nombre: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          nombre: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          nombre?: string
          updated_at?: string
        }
        Relationships: []
      }
      catalogo_condiciones: {
        Row: {
          activo: boolean
          bloquea: boolean
          condicion: string
          condicion_arbol: Json | null
          created_at: string
          id: string
          material_id: string | null
          mensaje: string
          opcion_id: string | null
          updated_at: string
          variable_id: string | null
          version_id: string
        }
        Insert: {
          activo?: boolean
          bloquea?: boolean
          condicion: string
          condicion_arbol?: never
          created_at?: string
          id?: string
          material_id?: string | null
          mensaje: string
          opcion_id?: string | null
          updated_at?: string
          variable_id?: string | null
          version_id: string
        }
        Update: {
          activo?: boolean
          bloquea?: boolean
          condicion?: string
          condicion_arbol?: never
          created_at?: string
          id?: string
          material_id?: string | null
          mensaje?: string
          opcion_id?: string | null
          updated_at?: string
          variable_id?: string | null
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogo_condiciones_material_id_version_id_fkey"
            columns: ["material_id", "version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_materiales"
            referencedColumns: ["id", "version_id"]
          },
          {
            foreignKeyName: "catalogo_condiciones_opcion_id_version_id_fkey"
            columns: ["opcion_id", "version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_opciones"
            referencedColumns: ["id", "version_id"]
          },
          {
            foreignKeyName: "catalogo_condiciones_variable_id_version_id_fkey"
            columns: ["variable_id", "version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_variables"
            referencedColumns: ["id", "version_id"]
          },
          {
            foreignKeyName: "catalogo_condiciones_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_versiones"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogo_costos: {
        Row: {
          activo: boolean
          costo: number
          creado_por: string
          created_at: string
          id: string
          moneda: Database["public"]["Enums"]["moneda"]
          updated_at: string
          variante_id: string
        }
        Insert: {
          activo?: boolean
          costo: number
          creado_por: string
          created_at?: string
          id?: string
          moneda: Database["public"]["Enums"]["moneda"]
          updated_at?: string
          variante_id: string
        }
        Update: {
          activo?: boolean
          costo?: number
          creado_por?: string
          created_at?: string
          id?: string
          moneda?: Database["public"]["Enums"]["moneda"]
          updated_at?: string
          variante_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogo_costos_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogo_costos_variante_id_fkey"
            columns: ["variante_id"]
            isOneToOne: false
            referencedRelation: "catalogo_variantes"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogo_insumos: {
        Row: {
          activo: boolean
          categoria_id: string
          con_color: boolean
          created_at: string
          espesor: number | null
          id: string
          nombre: string
          peso: number | null
          tipo: Database["public"]["Enums"]["tipo_catalogo"]
          unidad: Database["public"]["Enums"]["unidad_insumo"]
          updated_at: string
        }
        Insert: {
          activo?: boolean
          categoria_id: string
          con_color?: boolean
          created_at?: string
          espesor?: number | null
          id?: string
          nombre: string
          peso?: number | null
          tipo: Database["public"]["Enums"]["tipo_catalogo"]
          unidad: Database["public"]["Enums"]["unidad_insumo"]
          updated_at?: string
        }
        Update: {
          activo?: boolean
          categoria_id?: string
          con_color?: boolean
          created_at?: string
          espesor?: number | null
          id?: string
          nombre?: string
          peso?: number | null
          tipo?: Database["public"]["Enums"]["tipo_catalogo"]
          unidad?: Database["public"]["Enums"]["unidad_insumo"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogo_insumos_categoria_id_tipo_fkey"
            columns: ["categoria_id", "tipo"]
            isOneToOne: false
            referencedRelation: "catalogo_categorias"
            referencedColumns: ["id", "tipo"]
          },
        ]
      }
      catalogo_materiales: {
        Row: {
          activo: boolean
          alto: string | null
          alto_arbol: Json | null
          ancho: string | null
          ancho_arbol: Json | null
          area: string | null
          area_arbol: Json | null
          cantidad: string
          cantidad_arbol: Json | null
          created_at: string
          cuenta_espesor: boolean
          cuenta_peso: boolean
          eleccion: string | null
          eleccion_arbol: Json | null
          id: string
          insumo_id: string | null
          medida: string | null
          medida_arbol: Json | null
          nombre: string | null
          orden: number
          pieza_id: string
          secundario: boolean
          sigue_material_id: string | null
          sin_eleccion: boolean
          tipo: Database["public"]["Enums"]["tipo_material"]
          updated_at: string
          version_id: string
        }
        Insert: {
          activo?: boolean
          alto?: string | null
          alto_arbol?: never
          ancho?: string | null
          ancho_arbol?: never
          area?: string | null
          area_arbol?: never
          cantidad?: string
          cantidad_arbol?: never
          created_at?: string
          cuenta_espesor?: boolean
          cuenta_peso?: boolean
          eleccion?: string | null
          eleccion_arbol?: never
          id?: string
          insumo_id?: string | null
          medida?: string | null
          medida_arbol?: never
          nombre?: string | null
          orden?: number
          pieza_id: string
          secundario?: boolean
          sigue_material_id?: string | null
          sin_eleccion?: boolean
          tipo?: Database["public"]["Enums"]["tipo_material"]
          updated_at?: string
          version_id: string
        }
        Update: {
          activo?: boolean
          alto?: string | null
          alto_arbol?: never
          ancho?: string | null
          ancho_arbol?: never
          area?: string | null
          area_arbol?: never
          cantidad?: string
          cantidad_arbol?: never
          created_at?: string
          cuenta_espesor?: boolean
          cuenta_peso?: boolean
          eleccion?: string | null
          eleccion_arbol?: never
          id?: string
          insumo_id?: string | null
          medida?: string | null
          medida_arbol?: never
          nombre?: string | null
          orden?: number
          pieza_id?: string
          secundario?: boolean
          sigue_material_id?: string | null
          sin_eleccion?: boolean
          tipo?: Database["public"]["Enums"]["tipo_material"]
          updated_at?: string
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogo_materiales_insumo_id_fkey"
            columns: ["insumo_id"]
            isOneToOne: false
            referencedRelation: "catalogo_insumos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogo_materiales_pieza_id_version_id_fkey"
            columns: ["pieza_id", "version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_piezas"
            referencedColumns: ["id", "version_id"]
          },
          {
            foreignKeyName: "catalogo_materiales_sigue_material_id_version_id_fkey"
            columns: ["sigue_material_id", "version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_materiales"
            referencedColumns: ["id", "version_id"]
          },
          {
            foreignKeyName: "catalogo_materiales_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_versiones"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogo_opciones: {
        Row: {
          activo: boolean
          alto: string | null
          alto_arbol: Json | null
          ancho: string | null
          ancho_arbol: Json | null
          area: string | null
          area_arbol: Json | null
          cantidad: string | null
          cantidad_arbol: Json | null
          created_at: string
          id: string
          insumo_id: string | null
          material_id: string
          medida: string | null
          medida_arbol: Json | null
          orden: number
          predeterminada: boolean
          sigue_opcion_id: string | null
          updated_at: string
          version_id: string
        }
        Insert: {
          activo?: boolean
          alto?: string | null
          alto_arbol?: never
          ancho?: string | null
          ancho_arbol?: never
          area?: string | null
          area_arbol?: never
          cantidad?: string | null
          cantidad_arbol?: never
          created_at?: string
          id?: string
          insumo_id?: string | null
          material_id: string
          medida?: string | null
          medida_arbol?: never
          orden?: number
          predeterminada?: boolean
          sigue_opcion_id?: string | null
          updated_at?: string
          version_id: string
        }
        Update: {
          activo?: boolean
          alto?: string | null
          alto_arbol?: never
          ancho?: string | null
          ancho_arbol?: never
          area?: string | null
          area_arbol?: never
          cantidad?: string | null
          cantidad_arbol?: never
          created_at?: string
          id?: string
          insumo_id?: string | null
          material_id?: string
          medida?: string | null
          medida_arbol?: never
          orden?: number
          predeterminada?: boolean
          sigue_opcion_id?: string | null
          updated_at?: string
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogo_opciones_insumo_id_fkey"
            columns: ["insumo_id"]
            isOneToOne: false
            referencedRelation: "catalogo_insumos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogo_opciones_material_id_version_id_fkey"
            columns: ["material_id", "version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_materiales"
            referencedColumns: ["id", "version_id"]
          },
          {
            foreignKeyName: "catalogo_opciones_sigue_opcion_id_version_id_fkey"
            columns: ["sigue_opcion_id", "version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_opciones"
            referencedColumns: ["id", "version_id"]
          },
          {
            foreignKeyName: "catalogo_opciones_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_versiones"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogo_paquetes: {
        Row: {
          activo: boolean
          baja_insumo_id: string | null
          baja_variante_id: string | null
          created_at: string
          id: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          baja_insumo_id?: string | null
          baja_variante_id?: string | null
          created_at?: string
          id?: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          baja_insumo_id?: string | null
          baja_variante_id?: string | null
          created_at?: string
          id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogo_paquetes_baja_insumo_id_fkey"
            columns: ["baja_insumo_id"]
            isOneToOne: false
            referencedRelation: "catalogo_insumos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogo_paquetes_baja_variante_id_fkey"
            columns: ["baja_variante_id"]
            isOneToOne: false
            referencedRelation: "catalogo_variantes"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogo_piezas: {
        Row: {
          activo: boolean
          calcula_espesor: boolean
          cantidad: string
          cantidad_arbol: Json | null
          created_at: string
          espesor_a_produccion: boolean
          id: string
          incluida: boolean
          nombre: string
          opcional: boolean
          orden: number
          peso_a_produccion: boolean
          requiere_pieza_id: string | null
          secundario: boolean
          updated_at: string
          version_id: string
        }
        Insert: {
          activo?: boolean
          calcula_espesor?: boolean
          cantidad?: string
          cantidad_arbol?: never
          created_at?: string
          espesor_a_produccion?: boolean
          id?: string
          incluida?: boolean
          nombre: string
          opcional?: boolean
          orden?: number
          peso_a_produccion?: boolean
          requiere_pieza_id?: string | null
          secundario?: boolean
          updated_at?: string
          version_id: string
        }
        Update: {
          activo?: boolean
          calcula_espesor?: boolean
          cantidad?: string
          cantidad_arbol?: never
          created_at?: string
          espesor_a_produccion?: boolean
          id?: string
          incluida?: boolean
          nombre?: string
          opcional?: boolean
          orden?: number
          peso_a_produccion?: boolean
          requiere_pieza_id?: string | null
          secundario?: boolean
          updated_at?: string
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogo_piezas_requiere_pieza_id_version_id_fkey"
            columns: ["requiere_pieza_id", "version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_piezas"
            referencedColumns: ["id", "version_id"]
          },
          {
            foreignKeyName: "catalogo_piezas_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_versiones"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogo_porcentajes: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          updated_at?: string
        }
        Relationships: []
      }
      catalogo_porcentajes_valores: {
        Row: {
          activo: boolean
          categorias: string[]
          creado_por: string
          created_at: string
          de_baja: boolean
          id: string
          minimo: number | null
          minimo_moneda: Database["public"]["Enums"]["moneda"] | null
          minimo_por: Database["public"]["Enums"]["alcance_minimo"] | null
          nombre: string
          opcional: boolean
          paso: number
          porcentaje: number
          porcentaje_id: string
          revierte_id: string | null
          updated_at: string
        }
        Insert: {
          activo?: boolean
          categorias?: string[]
          creado_por: string
          created_at?: string
          de_baja?: boolean
          id?: string
          minimo?: number | null
          minimo_moneda?: Database["public"]["Enums"]["moneda"] | null
          minimo_por?: Database["public"]["Enums"]["alcance_minimo"] | null
          nombre: string
          opcional?: boolean
          paso: number
          porcentaje: number
          porcentaje_id: string
          revierte_id?: string | null
          updated_at?: string
        }
        Update: {
          activo?: boolean
          categorias?: string[]
          creado_por?: string
          created_at?: string
          de_baja?: boolean
          id?: string
          minimo?: number | null
          minimo_moneda?: Database["public"]["Enums"]["moneda"] | null
          minimo_por?: Database["public"]["Enums"]["alcance_minimo"] | null
          nombre?: string
          opcional?: boolean
          paso?: number
          porcentaje?: number
          porcentaje_id?: string
          revierte_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogo_porcentajes_valores_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogo_porcentajes_valores_porcentaje_id_fkey"
            columns: ["porcentaje_id"]
            isOneToOne: false
            referencedRelation: "catalogo_porcentajes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogo_porcentajes_valores_revierte_id_fkey"
            columns: ["revierte_id"]
            isOneToOne: false
            referencedRelation: "catalogo_porcentajes_valores"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogo_variables: {
        Row: {
          a_produccion: boolean
          activo: boolean
          created_at: string
          es_cantidad: boolean
          es_lista: boolean
          formula: string | null
          formula_arbol: Json | null
          id: string
          ingresa_vendedor: boolean
          maximo: number | null
          minimo: number | null
          nombre: string
          orden: number
          pieza_id: string | null
          secundario: boolean
          updated_at: string
          valor_predeterminado: string | null
          valores: string[]
          version_id: string
        }
        Insert: {
          a_produccion?: boolean
          activo?: boolean
          created_at?: string
          es_cantidad?: boolean
          es_lista?: boolean
          formula?: string | null
          formula_arbol?: never
          id?: string
          ingresa_vendedor?: boolean
          maximo?: number | null
          minimo?: number | null
          nombre: string
          orden?: number
          pieza_id?: string | null
          secundario?: boolean
          updated_at?: string
          valor_predeterminado?: string | null
          valores?: string[]
          version_id: string
        }
        Update: {
          a_produccion?: boolean
          activo?: boolean
          created_at?: string
          es_cantidad?: boolean
          es_lista?: boolean
          formula?: string | null
          formula_arbol?: never
          id?: string
          ingresa_vendedor?: boolean
          maximo?: number | null
          minimo?: number | null
          nombre?: string
          orden?: number
          pieza_id?: string | null
          secundario?: boolean
          updated_at?: string
          valor_predeterminado?: string | null
          valores?: string[]
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogo_variables_pieza_id_version_id_fkey"
            columns: ["pieza_id", "version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_piezas"
            referencedColumns: ["id", "version_id"]
          },
          {
            foreignKeyName: "catalogo_variables_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_versiones"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogo_variantes: {
        Row: {
          activo: boolean
          color_id: string | null
          created_at: string
          id: string
          insumo_id: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          color_id?: string | null
          created_at?: string
          id?: string
          insumo_id: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          color_id?: string | null
          created_at?: string
          id?: string
          insumo_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogo_variantes_color_id_fkey"
            columns: ["color_id"]
            isOneToOne: false
            referencedRelation: "catalogo_colores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogo_variantes_insumo_id_fkey"
            columns: ["insumo_id"]
            isOneToOne: false
            referencedRelation: "catalogo_insumos"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogo_versiones: {
        Row: {
          activo: boolean
          categoria_id: string
          categoria_tipo: Database["public"]["Enums"]["tipo_catalogo"] | null
          created_at: string
          enviada: boolean | null
          estado: Database["public"]["Enums"]["estado_version_catalogo"]
          id: string
          nombre: string
          numero: number
          paquete_id: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          categoria_id: string
          categoria_tipo?: never
          created_at?: string
          enviada?: never
          estado?: Database["public"]["Enums"]["estado_version_catalogo"]
          id?: string
          nombre: string
          numero: number
          paquete_id: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          categoria_id?: string
          categoria_tipo?: never
          created_at?: string
          enviada?: never
          estado?: Database["public"]["Enums"]["estado_version_catalogo"]
          id?: string
          nombre?: string
          numero?: number
          paquete_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogo_versiones_categoria_id_categoria_tipo_fkey"
            columns: ["categoria_id", "categoria_tipo"]
            isOneToOne: false
            referencedRelation: "catalogo_categorias"
            referencedColumns: ["id", "tipo"]
          },
          {
            foreignKeyName: "catalogo_versiones_paquete_id_fkey"
            columns: ["paquete_id"]
            isOneToOne: false
            referencedRelation: "catalogo_paquetes"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogo_versiones_colores: {
        Row: {
          activo: boolean
          base: boolean
          color_id: string
          created_at: string
          id: string
          updated_at: string
          version_id: string
        }
        Insert: {
          activo?: boolean
          base?: boolean
          color_id: string
          created_at?: string
          id?: string
          updated_at?: string
          version_id: string
        }
        Update: {
          activo?: boolean
          base?: boolean
          color_id?: string
          created_at?: string
          id?: string
          updated_at?: string
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogo_versiones_colores_color_id_fkey"
            columns: ["color_id"]
            isOneToOne: false
            referencedRelation: "catalogo_colores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogo_versiones_colores_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_versiones"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogo_versiones_historia: {
        Row: {
          accion: Database["public"]["Enums"]["accion_version_catalogo"]
          activo: boolean
          creado_por: string
          created_at: string
          id: string
          motivo: string | null
          updated_at: string
          version_id: string
        }
        Insert: {
          accion: Database["public"]["Enums"]["accion_version_catalogo"]
          activo?: boolean
          creado_por: string
          created_at?: string
          id?: string
          motivo?: string | null
          updated_at?: string
          version_id: string
        }
        Update: {
          accion?: Database["public"]["Enums"]["accion_version_catalogo"]
          activo?: boolean
          creado_por?: string
          created_at?: string
          id?: string
          motivo?: string | null
          updated_at?: string
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogo_versiones_historia_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogo_versiones_historia_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "catalogo_versiones"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos_accesos: {
        Row: {
          created_at: string
          id: string
          persona_id: string
          usuario_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          persona_id: string
          usuario_id: string
        }
        Update: {
          created_at?: string
          id?: string
          persona_id?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "contactos_accesos_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "contactos_personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_accesos_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos_ediciones: {
        Row: {
          actor_id: string | null
          anterior: string | null
          campo: string
          created_at: string
          empresa_id: string | null
          id: string
          nuevo: string | null
          persona_id: string | null
        }
        Insert: {
          actor_id?: string | null
          anterior?: string | null
          campo: string
          created_at?: string
          empresa_id?: string | null
          id?: string
          nuevo?: string | null
          persona_id?: string | null
        }
        Update: {
          actor_id?: string | null
          anterior?: string | null
          campo?: string
          created_at?: string
          empresa_id?: string | null
          id?: string
          nuevo?: string | null
          persona_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contactos_ediciones_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_ediciones_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "contactos_empresas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_ediciones_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "contactos_personas"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos_empresa_equipos: {
        Row: {
          activo: boolean
          compartida_por: string
          created_at: string
          empresa_id: string
          equipo_id: string
          id: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          compartida_por: string
          created_at?: string
          empresa_id: string
          equipo_id: string
          id?: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          compartida_por?: string
          created_at?: string
          empresa_id?: string
          equipo_id?: string
          id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "contactos_empresa_equipos_compartida_por_fkey"
            columns: ["compartida_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_empresa_equipos_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "contactos_empresas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_empresa_equipos_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos_empresas: {
        Row: {
          activo: boolean
          congelada: boolean
          congelada_antes: Json | null
          creado_por: string
          created_at: string
          email: string | null
          equipo_id: string | null
          fusionada_en: string | null
          id: string
          misma_que: string | null
          nombre: string
          notas: string | null
          rechazo_motivo: string | null
          telefono: string | null
          updated_at: string
          web: string | null
        }
        Insert: {
          activo?: boolean
          congelada?: boolean
          congelada_antes?: Json | null
          creado_por?: string
          created_at?: string
          email?: string | null
          equipo_id?: string | null
          fusionada_en?: string | null
          id?: string
          misma_que?: string | null
          nombre: string
          notas?: string | null
          rechazo_motivo?: string | null
          telefono?: string | null
          updated_at?: string
          web?: string | null
        }
        Update: {
          activo?: boolean
          congelada?: boolean
          congelada_antes?: Json | null
          creado_por?: string
          created_at?: string
          email?: string | null
          equipo_id?: string | null
          fusionada_en?: string | null
          id?: string
          misma_que?: string | null
          nombre?: string
          notas?: string | null
          rechazo_motivo?: string | null
          telefono?: string | null
          updated_at?: string
          web?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contactos_empresas_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_empresas_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_empresas_fusionada_en_fkey"
            columns: ["fusionada_en"]
            isOneToOne: false
            referencedRelation: "contactos_empresas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_empresas_misma_que_fkey"
            columns: ["misma_que"]
            isOneToOne: false
            referencedRelation: "contactos_empresas"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos_persona_empresa: {
        Row: {
          activo: boolean
          cargo: string | null
          creado_por: string | null
          created_at: string
          desde: string
          empresa_id: string
          hasta: string | null
          id: string
          persona_id: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          cargo?: string | null
          creado_por?: string | null
          created_at?: string
          desde?: string
          empresa_id: string
          hasta?: string | null
          id?: string
          persona_id: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          cargo?: string | null
          creado_por?: string | null
          created_at?: string
          desde?: string
          empresa_id?: string
          hasta?: string | null
          id?: string
          persona_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "contactos_persona_empresa_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_persona_empresa_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "contactos_empresas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_persona_empresa_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "contactos_personas"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos_personas: {
        Row: {
          activo: boolean
          congelada: boolean
          congelada_antes: Json | null
          creado_por: string
          created_at: string
          email: string | null
          fusionada_en: string | null
          id: string
          misma_que: string | null
          nombre: string
          notas: string | null
          rechazo_motivo: string | null
          responsable_id: string
          telefono: string | null
          updated_at: string
        }
        Insert: {
          activo?: boolean
          congelada?: boolean
          congelada_antes?: Json | null
          creado_por?: string
          created_at?: string
          email?: string | null
          fusionada_en?: string | null
          id?: string
          misma_que?: string | null
          nombre: string
          notas?: string | null
          rechazo_motivo?: string | null
          responsable_id?: string
          telefono?: string | null
          updated_at?: string
        }
        Update: {
          activo?: boolean
          congelada?: boolean
          congelada_antes?: Json | null
          creado_por?: string
          created_at?: string
          email?: string | null
          fusionada_en?: string | null
          id?: string
          misma_que?: string | null
          nombre?: string
          notas?: string | null
          rechazo_motivo?: string | null
          responsable_id?: string
          telefono?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "contactos_personas_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_personas_fusionada_en_fkey"
            columns: ["fusionada_en"]
            isOneToOne: false
            referencedRelation: "contactos_personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_personas_misma_que_fkey"
            columns: ["misma_que"]
            isOneToOne: false
            referencedRelation: "contactos_personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_personas_responsable_id_fkey"
            columns: ["responsable_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos_vinculos: {
        Row: {
          activo: boolean
          creado_por: string | null
          created_at: string
          desde: string
          empresa_id: string | null
          ente: string
          fusionado_en: string | null
          hasta: string | null
          id: string
          persona_id: string | null
          registro_id: string
          roles: string[]
          updated_at: string
        }
        Insert: {
          activo?: boolean
          creado_por?: string | null
          created_at?: string
          desde?: string
          empresa_id?: string | null
          ente: string
          fusionado_en?: string | null
          hasta?: string | null
          id?: string
          persona_id?: string | null
          registro_id: string
          roles: string[]
          updated_at?: string
        }
        Update: {
          activo?: boolean
          creado_por?: string | null
          created_at?: string
          desde?: string
          empresa_id?: string | null
          ente?: string
          fusionado_en?: string | null
          hasta?: string | null
          id?: string
          persona_id?: string | null
          registro_id?: string
          roles?: string[]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "contactos_vinculos_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_vinculos_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "contactos_empresas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_vinculos_ente_fkey"
            columns: ["ente"]
            isOneToOne: false
            referencedRelation: "entes"
            referencedColumns: ["codigo"]
          },
          {
            foreignKeyName: "contactos_vinculos_fusionado_en_fkey"
            columns: ["fusionado_en"]
            isOneToOne: false
            referencedRelation: "contactos_vinculos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_vinculos_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "contactos_personas"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos_vinculos_guardados: {
        Row: {
          a_empresa_id: string | null
          activo: boolean
          cargado_por: string
          cargo: string | null
          created_at: string
          empresa_id: string | null
          ente: string | null
          id: string
          persona_id: string | null
          registro_id: string | null
          resultado: string | null
          roles: string[] | null
          updated_at: string
        }
        Insert: {
          a_empresa_id?: string | null
          activo?: boolean
          cargado_por: string
          cargo?: string | null
          created_at?: string
          empresa_id?: string | null
          ente?: string | null
          id?: string
          persona_id?: string | null
          registro_id?: string | null
          resultado?: string | null
          roles?: string[] | null
          updated_at?: string
        }
        Update: {
          a_empresa_id?: string | null
          activo?: boolean
          cargado_por?: string
          cargo?: string | null
          created_at?: string
          empresa_id?: string | null
          ente?: string | null
          id?: string
          persona_id?: string | null
          registro_id?: string | null
          resultado?: string | null
          roles?: string[] | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "contactos_vinculos_guardados_a_empresa_id_fkey"
            columns: ["a_empresa_id"]
            isOneToOne: false
            referencedRelation: "contactos_empresas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_vinculos_guardados_cargado_por_fkey"
            columns: ["cargado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_vinculos_guardados_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "contactos_empresas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_vinculos_guardados_ente_fkey"
            columns: ["ente"]
            isOneToOne: false
            referencedRelation: "entes"
            referencedColumns: ["codigo"]
          },
          {
            foreignKeyName: "contactos_vinculos_guardados_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "contactos_personas"
            referencedColumns: ["id"]
          },
        ]
      }
      entes: {
        Row: {
          activo: boolean
          codigo: string
          created_at: string
          datos: string[]
          disparos: Database["public"]["Enums"]["tipo_evento"][]
          dueno: string | null
          estados: unknown
          id: string
          modulo: string
          roles: string[]
          ruta: string
          submodulo: string
          tabla: unknown
          updated_at: string
        }
        Insert: {
          activo?: boolean
          codigo: string
          created_at?: string
          datos?: string[]
          disparos?: Database["public"]["Enums"]["tipo_evento"][]
          dueno?: string | null
          estados?: unknown
          id?: string
          modulo: string
          roles?: string[]
          ruta: string
          submodulo: string
          tabla: unknown
          updated_at?: string
        }
        Update: {
          activo?: boolean
          codigo?: string
          created_at?: string
          datos?: string[]
          disparos?: Database["public"]["Enums"]["tipo_evento"][]
          dueno?: string | null
          estados?: unknown
          id?: string
          modulo?: string
          roles?: string[]
          ruta?: string
          submodulo?: string
          tabla?: unknown
          updated_at?: string
        }
        Relationships: []
      }
      equipos: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          nombre: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          nombre: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          nombre?: string
          updated_at?: string
        }
        Relationships: []
      }
      equipos_miembros: {
        Row: {
          activo: boolean
          created_at: string
          equipo_id: string
          id: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          equipo_id: string
          id?: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          equipo_id?: string
          id?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "equipos_miembros_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "equipos_miembros_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      eventos: {
        Row: {
          actor_id: string | null
          created_at: string
          detalle: Json
          ente: string
          evento: Database["public"]["Enums"]["tipo_evento"]
          id: string
          registro_id: string
        }
        Insert: {
          actor_id?: string | null
          created_at?: string
          detalle?: Json
          ente: string
          evento: Database["public"]["Enums"]["tipo_evento"]
          id?: string
          registro_id: string
        }
        Update: {
          actor_id?: string | null
          created_at?: string
          detalle?: Json
          ente?: string
          evento?: Database["public"]["Enums"]["tipo_evento"]
          id?: string
          registro_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "eventos_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "eventos_ente_fkey"
            columns: ["ente"]
            isOneToOne: false
            referencedRelation: "entes"
            referencedColumns: ["codigo"]
          },
        ]
      }
      monedas_consultas: {
        Row: {
          activo: boolean
          created_at: string
          error: string | null
          forzada: boolean
          id: string
          ok: boolean | null
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          error?: string | null
          forzada: boolean
          id?: string
          ok?: boolean | null
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          error?: string | null
          forzada?: boolean
          id?: string
          ok?: boolean | null
          updated_at?: string
        }
        Relationships: []
      }
      monedas_principal: {
        Row: {
          activo: boolean
          creado_por: string
          created_at: string
          id: string
          moneda: Database["public"]["Enums"]["moneda"]
          updated_at: string
        }
        Insert: {
          activo?: boolean
          creado_por: string
          created_at?: string
          id?: string
          moneda: Database["public"]["Enums"]["moneda"]
          updated_at?: string
        }
        Update: {
          activo?: boolean
          creado_por?: string
          created_at?: string
          id?: string
          moneda?: Database["public"]["Enums"]["moneda"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "monedas_principal_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      monedas_tipos_cambio: {
        Row: {
          activo: boolean
          confirmado_por: string | null
          creado_por: string | null
          created_at: string
          fecha: string
          id: string
          moneda: Database["public"]["Enums"]["moneda"]
          origen: Database["public"]["Enums"]["origen_tipo_cambio"]
          updated_at: string
          valor: number
          vigente_desde: string | null
        }
        Insert: {
          activo?: boolean
          confirmado_por?: string | null
          creado_por?: string | null
          created_at?: string
          fecha: string
          id?: string
          moneda: Database["public"]["Enums"]["moneda"]
          origen: Database["public"]["Enums"]["origen_tipo_cambio"]
          updated_at?: string
          valor: number
          vigente_desde?: string | null
        }
        Update: {
          activo?: boolean
          confirmado_por?: string | null
          creado_por?: string | null
          created_at?: string
          fecha?: string
          id?: string
          moneda?: Database["public"]["Enums"]["moneda"]
          origen?: Database["public"]["Enums"]["origen_tipo_cambio"]
          updated_at?: string
          valor?: number
          vigente_desde?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "monedas_tipos_cambio_confirmado_por_fkey"
            columns: ["confirmado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "monedas_tipos_cambio_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      obras: {
        Row: {
          activo: boolean
          compra_estimada: string | null
          congelada: boolean
          congelada_antes: Json | null
          creado_por: string
          created_at: string
          direccion: string
          equipo_id: string | null
          estado: Database["public"]["Enums"]["estado_obra"]
          estado_nota: string | null
          id: string
          localidad: string | null
          misma_que: string | null
          motivo_perdida: Database["public"]["Enums"]["motivo_perdida"] | null
          nombre: string
          notas: string | null
          origen: Database["public"]["Enums"]["origen_obra"]
          rechazo_motivo: string | null
          responsable_id: string
          tipo: Database["public"]["Enums"]["tipo_obra"]
          updated_at: string
        }
        Insert: {
          activo?: boolean
          compra_estimada?: string | null
          congelada?: boolean
          congelada_antes?: Json | null
          creado_por?: string
          created_at?: string
          direccion: string
          equipo_id?: string | null
          estado?: Database["public"]["Enums"]["estado_obra"]
          estado_nota?: string | null
          id?: string
          localidad?: string | null
          misma_que?: string | null
          motivo_perdida?: Database["public"]["Enums"]["motivo_perdida"] | null
          nombre: string
          notas?: string | null
          origen: Database["public"]["Enums"]["origen_obra"]
          rechazo_motivo?: string | null
          responsable_id?: string
          tipo: Database["public"]["Enums"]["tipo_obra"]
          updated_at?: string
        }
        Update: {
          activo?: boolean
          compra_estimada?: string | null
          congelada?: boolean
          congelada_antes?: Json | null
          creado_por?: string
          created_at?: string
          direccion?: string
          equipo_id?: string | null
          estado?: Database["public"]["Enums"]["estado_obra"]
          estado_nota?: string | null
          id?: string
          localidad?: string | null
          misma_que?: string | null
          motivo_perdida?: Database["public"]["Enums"]["motivo_perdida"] | null
          nombre?: string
          notas?: string | null
          origen?: Database["public"]["Enums"]["origen_obra"]
          rechazo_motivo?: string | null
          responsable_id?: string
          tipo?: Database["public"]["Enums"]["tipo_obra"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "obras_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "obras_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "obras_misma_que_fkey"
            columns: ["misma_que"]
            isOneToOne: false
            referencedRelation: "obras"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "obras_responsable_id_fkey"
            columns: ["responsable_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      obras_comisiones: {
        Row: {
          activo: boolean
          creado_por: string
          created_at: string
          id: string
          moneda: Database["public"]["Enums"]["moneda"] | null
          monto: number | null
          porcentaje: number | null
          updated_at: string
          vinculo_id: string
        }
        Insert: {
          activo?: boolean
          creado_por?: string
          created_at?: string
          id?: string
          moneda?: Database["public"]["Enums"]["moneda"] | null
          monto?: number | null
          porcentaje?: number | null
          updated_at?: string
          vinculo_id: string
        }
        Update: {
          activo?: boolean
          creado_por?: string
          created_at?: string
          id?: string
          moneda?: Database["public"]["Enums"]["moneda"] | null
          monto?: number | null
          porcentaje?: number | null
          updated_at?: string
          vinculo_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "obras_comisiones_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "obras_comisiones_vinculo_id_fkey"
            columns: ["vinculo_id"]
            isOneToOne: false
            referencedRelation: "contactos_vinculos"
            referencedColumns: ["id"]
          },
        ]
      }
      obras_participantes: {
        Row: {
          activo: boolean
          agregado_por: string | null
          created_at: string
          equipo_id: string | null
          id: string
          obra_id: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          agregado_por?: string | null
          created_at?: string
          equipo_id?: string | null
          id?: string
          obra_id: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          agregado_por?: string | null
          created_at?: string
          equipo_id?: string | null
          id?: string
          obra_id?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "obras_participantes_agregado_por_fkey"
            columns: ["agregado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "obras_participantes_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "obras_participantes_obra_id_fkey"
            columns: ["obra_id"]
            isOneToOne: false
            referencedRelation: "obras"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "obras_participantes_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      submodulo_reglas: {
        Row: {
          activo: boolean
          id: string
          otro_id: string
          submodulo_id: string
          tipo: Database["public"]["Enums"]["tipo_regla_submodulo"]
        }
        Insert: {
          activo?: boolean
          id?: string
          otro_id: string
          submodulo_id: string
          tipo: Database["public"]["Enums"]["tipo_regla_submodulo"]
        }
        Update: {
          activo?: boolean
          id?: string
          otro_id?: string
          submodulo_id?: string
          tipo?: Database["public"]["Enums"]["tipo_regla_submodulo"]
        }
        Relationships: [
          {
            foreignKeyName: "submodulo_reglas_otro_id_fkey"
            columns: ["otro_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "submodulo_reglas_submodulo_id_fkey"
            columns: ["submodulo_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
        ]
      }
      submodulos: {
        Row: {
          activo: boolean
          codigo: string
          created_at: string
          delegable: boolean
          id: string
          modulo: string
          nombre: string
          orden: number
          tipo: Database["public"]["Enums"]["tipo_submodulo"]
          updated_at: string
          vista_id: string | null
        }
        Insert: {
          activo?: boolean
          codigo: string
          created_at?: string
          delegable?: boolean
          id?: string
          modulo: string
          nombre: string
          orden?: number
          tipo: Database["public"]["Enums"]["tipo_submodulo"]
          updated_at?: string
          vista_id?: string | null
        }
        Update: {
          activo?: boolean
          codigo?: string
          created_at?: string
          delegable?: boolean
          id?: string
          modulo?: string
          nombre?: string
          orden?: number
          tipo?: Database["public"]["Enums"]["tipo_submodulo"]
          updated_at?: string
          vista_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "submodulos_vista_id_fkey"
            columns: ["vista_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas: {
        Row: {
          activo: boolean
          asignado_equipo_id: string | null
          asignado_id: string | null
          completa_evento: Database["public"]["Enums"]["tipo_evento"] | null
          completa_valor: string | null
          created_at: string
          descripcion: string | null
          equipo_id: string | null
          espera_hasta: string | null
          espera_motivo: string | null
          estado: Database["public"]["Enums"]["estado_tarea"]
          hilo_id: string
          id: string
          motivo_rechazo: string | null
          paso_anterior_id: string | null
          prioridad: Database["public"]["Enums"]["prioridad_tarea"]
          resultado: string | null
          titulo: string
          updated_at: string
          vence: string | null
          vence_dias: number | null
        }
        Insert: {
          activo?: boolean
          asignado_equipo_id?: string | null
          asignado_id?: string | null
          completa_evento?: Database["public"]["Enums"]["tipo_evento"] | null
          completa_valor?: string | null
          created_at?: string
          descripcion?: string | null
          equipo_id?: string | null
          espera_hasta?: string | null
          espera_motivo?: string | null
          estado?: Database["public"]["Enums"]["estado_tarea"]
          hilo_id: string
          id?: string
          motivo_rechazo?: string | null
          paso_anterior_id?: string | null
          prioridad?: Database["public"]["Enums"]["prioridad_tarea"]
          resultado?: string | null
          titulo: string
          updated_at?: string
          vence?: string | null
          vence_dias?: number | null
        }
        Update: {
          activo?: boolean
          asignado_equipo_id?: string | null
          asignado_id?: string | null
          completa_evento?: Database["public"]["Enums"]["tipo_evento"] | null
          completa_valor?: string | null
          created_at?: string
          descripcion?: string | null
          equipo_id?: string | null
          espera_hasta?: string | null
          espera_motivo?: string | null
          estado?: Database["public"]["Enums"]["estado_tarea"]
          hilo_id?: string
          id?: string
          motivo_rechazo?: string | null
          paso_anterior_id?: string | null
          prioridad?: Database["public"]["Enums"]["prioridad_tarea"]
          resultado?: string | null
          titulo?: string
          updated_at?: string
          vence?: string | null
          vence_dias?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "tareas_asignado_equipo_id_fkey"
            columns: ["asignado_equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_asignado_id_fkey"
            columns: ["asignado_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_hilo_id_fkey"
            columns: ["hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas_hilos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_paso_anterior_fk"
            columns: ["paso_anterior_id", "hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id", "hilo_id"]
          },
        ]
      }
      tareas_ediciones: {
        Row: {
          activo: boolean
          actor_id: string | null
          anterior: string | null
          campo: string
          created_at: string
          hilo_id: string
          id: string
          nuevo: string | null
          ocultada_at: string | null
          ocultada_por: string | null
          tarea_id: string | null
          updated_at: string
        }
        Insert: {
          activo?: boolean
          actor_id?: string | null
          anterior?: string | null
          campo: string
          created_at?: string
          hilo_id: string
          id?: string
          nuevo?: string | null
          ocultada_at?: string | null
          ocultada_por?: string | null
          tarea_id?: string | null
          updated_at?: string
        }
        Update: {
          activo?: boolean
          actor_id?: string | null
          anterior?: string | null
          campo?: string
          created_at?: string
          hilo_id?: string
          id?: string
          nuevo?: string | null
          ocultada_at?: string | null
          ocultada_por?: string | null
          tarea_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_ediciones_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_ediciones_hilo_id_fkey"
            columns: ["hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas_hilos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_ediciones_ocultada_por_fkey"
            columns: ["ocultada_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_ediciones_tarea_fk"
            columns: ["tarea_id", "hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id", "hilo_id"]
          },
        ]
      }
      tareas_hilos: {
        Row: {
          activo: boolean
          created_at: string
          equipo_id: string | null
          estado: Database["public"]["Enums"]["estado_hilo"]
          id: string
          plantilla_id: string | null
          recurrencia_cantidad: number | null
          recurrencia_de: string | null
          recurrencia_unidad:
            | Database["public"]["Enums"]["recurrencia_unidad"]
            | null
          registro_ente: string | null
          registro_id: string | null
          responsable_id: string
          resultado: string | null
          titulo: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          equipo_id?: string | null
          estado?: Database["public"]["Enums"]["estado_hilo"]
          id?: string
          plantilla_id?: string | null
          recurrencia_cantidad?: number | null
          recurrencia_de?: string | null
          recurrencia_unidad?:
            | Database["public"]["Enums"]["recurrencia_unidad"]
            | null
          registro_ente?: string | null
          registro_id?: string | null
          responsable_id?: string
          resultado?: string | null
          titulo: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          equipo_id?: string | null
          estado?: Database["public"]["Enums"]["estado_hilo"]
          id?: string
          plantilla_id?: string | null
          recurrencia_cantidad?: number | null
          recurrencia_de?: string | null
          recurrencia_unidad?:
            | Database["public"]["Enums"]["recurrencia_unidad"]
            | null
          registro_ente?: string | null
          registro_id?: string | null
          responsable_id?: string
          resultado?: string | null
          titulo?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_hilos_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_hilos_recurrencia_de_fkey"
            columns: ["recurrencia_de"]
            isOneToOne: false
            referencedRelation: "tareas_hilos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_hilos_responsable_id_fkey"
            columns: ["responsable_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_notas: {
        Row: {
          activo: boolean
          autor_id: string
          created_at: string
          hilo_id: string
          id: string
          ocultada_at: string | null
          ocultada_por: string | null
          tarea_id: string | null
          texto: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          autor_id?: string
          created_at?: string
          hilo_id: string
          id?: string
          ocultada_at?: string | null
          ocultada_por?: string | null
          tarea_id?: string | null
          texto: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          autor_id?: string
          created_at?: string
          hilo_id?: string
          id?: string
          ocultada_at?: string | null
          ocultada_por?: string | null
          tarea_id?: string | null
          texto?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_notas_autor_id_fkey"
            columns: ["autor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_notas_hilo_id_fkey"
            columns: ["hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas_hilos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_notas_ocultada_por_fkey"
            columns: ["ocultada_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_notas_tarea_fk"
            columns: ["tarea_id", "hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id", "hilo_id"]
          },
        ]
      }
      tareas_plantillas: {
        Row: {
          activo: boolean
          copiada_de: string | null
          created_at: string
          descripcion: string | null
          disparo_activo: boolean
          disparo_estado: string | null
          disparo_evento: Database["public"]["Enums"]["tipo_evento"] | null
          dueno_id: string
          id: string
          nombre: string
          publicada: boolean
          sobre: string | null
          updated_at: string
        }
        Insert: {
          activo?: boolean
          copiada_de?: string | null
          created_at?: string
          descripcion?: string | null
          disparo_activo?: boolean
          disparo_estado?: string | null
          disparo_evento?: Database["public"]["Enums"]["tipo_evento"] | null
          dueno_id?: string
          id?: string
          nombre: string
          publicada?: boolean
          sobre?: string | null
          updated_at?: string
        }
        Update: {
          activo?: boolean
          copiada_de?: string | null
          created_at?: string
          descripcion?: string | null
          disparo_activo?: boolean
          disparo_estado?: string | null
          disparo_evento?: Database["public"]["Enums"]["tipo_evento"] | null
          dueno_id?: string
          id?: string
          nombre?: string
          publicada?: boolean
          sobre?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_plantillas_copiada_de_fkey"
            columns: ["copiada_de"]
            isOneToOne: false
            referencedRelation: "tareas_plantillas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_plantillas_dueno_id_fkey"
            columns: ["dueno_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_plantillas_pasos: {
        Row: {
          activo: boolean
          asignado_equipo_id: string | null
          asignado_id: string | null
          completa_evento: Database["public"]["Enums"]["tipo_evento"] | null
          completa_valor: string | null
          condicion: string | null
          created_at: string
          descripcion: string | null
          espera_anterior: boolean
          id: string
          orden: number
          plantilla_id: string
          prioridad: Database["public"]["Enums"]["prioridad_tarea"]
          titulo: string
          updated_at: string
          vence_dias: number | null
        }
        Insert: {
          activo?: boolean
          asignado_equipo_id?: string | null
          asignado_id?: string | null
          completa_evento?: Database["public"]["Enums"]["tipo_evento"] | null
          completa_valor?: string | null
          condicion?: string | null
          created_at?: string
          descripcion?: string | null
          espera_anterior?: boolean
          id?: string
          orden: number
          plantilla_id: string
          prioridad?: Database["public"]["Enums"]["prioridad_tarea"]
          titulo: string
          updated_at?: string
          vence_dias?: number | null
        }
        Update: {
          activo?: boolean
          asignado_equipo_id?: string | null
          asignado_id?: string | null
          completa_evento?: Database["public"]["Enums"]["tipo_evento"] | null
          completa_valor?: string | null
          condicion?: string | null
          created_at?: string
          descripcion?: string | null
          espera_anterior?: boolean
          id?: string
          orden?: number
          plantilla_id?: string
          prioridad?: Database["public"]["Enums"]["prioridad_tarea"]
          titulo?: string
          updated_at?: string
          vence_dias?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "tareas_plantillas_pasos_asignado_equipo_id_fkey"
            columns: ["asignado_equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_plantillas_pasos_asignado_id_fkey"
            columns: ["asignado_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_plantillas_pasos_plantilla_id_fkey"
            columns: ["plantilla_id"]
            isOneToOne: false
            referencedRelation: "tareas_plantillas"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_vinculos: {
        Row: {
          activo: boolean
          created_at: string
          ente: string
          id: string
          registro_id: string
          tarea_id: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          ente: string
          id?: string
          registro_id: string
          tarea_id: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          ente?: string
          id?: string
          registro_id?: string
          tarea_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_vinculos_ente_fkey"
            columns: ["ente"]
            isOneToOne: false
            referencedRelation: "entes"
            referencedColumns: ["codigo"]
          },
          {
            foreignKeyName: "tareas_vinculos_tarea_id_fkey"
            columns: ["tarea_id"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_notificaciones: {
        Row: {
          activo: boolean
          actor_id: string | null
          created_at: string
          entidad: string
          entidad_id: string
          id: string
          leida_at: string | null
          tipo: Database["public"]["Enums"]["tipo_notificacion"]
          updated_at: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          actor_id?: string | null
          created_at?: string
          entidad: string
          entidad_id: string
          id?: string
          leida_at?: string | null
          tipo: Database["public"]["Enums"]["tipo_notificacion"]
          updated_at?: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          actor_id?: string | null
          created_at?: string
          entidad?: string
          entidad_id?: string
          id?: string
          leida_at?: string | null
          tipo?: Database["public"]["Enums"]["tipo_notificacion"]
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_notificaciones_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "usuario_notificaciones_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_submodulos: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          otorgada_por: string | null
          submodulo_id: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          otorgada_por?: string | null
          submodulo_id: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          otorgada_por?: string | null
          submodulo_id?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_submodulos_otorgada_por_fkey"
            columns: ["otorgada_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "usuario_submodulos_submodulo_id_fkey"
            columns: ["submodulo_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "usuario_submodulos_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_tutorial: {
        Row: {
          created_at: string
          id: string
          paso: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          paso: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          created_at?: string
          id?: string
          paso?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_tutorial_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_widgets: {
        Row: {
          created_at: string
          id: string
          updated_at: string
          usuario_id: string
          visible: boolean
          widget_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          updated_at?: string
          usuario_id: string
          visible?: boolean
          widget_id: string
        }
        Update: {
          created_at?: string
          id?: string
          updated_at?: string
          usuario_id?: string
          visible?: boolean
          widget_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_widgets_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuarios: {
        Row: {
          activo: boolean
          created_at: string
          email: string
          id: string
          nombre: string
          telefono: string | null
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          email: string
          id: string
          nombre: string
          telefono?: string | null
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          email?: string
          id?: string
          nombre?: string
          telefono?: string | null
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      asignar_equipo: {
        Args: {
          p_admin: string
          p_agenda_al_jefe?: boolean
          p_equipo: string | null
          p_usuario: string
        }
        Returns: undefined
      }
      asignar_submodulos: {
        Args: {
          p_admin: string
          p_submodulos: string[]
          p_tomar?: string[]
          p_usuario: string
        }
        Returns: undefined
      }
      buscar_registros: {
        Args: { p_modulo: string; p_texto: string }
        Returns: {
          detalle: string
          ente: string
          etiqueta: string
          href: string
          registro_id: string
        }[]
      }
      catalogo_baja_aviso: {
        Args: { p_insumo: string; p_variante?: string }
        Returns: Json
      }
      catalogo_baja_efecto: {
        Args: { p_insumo: string; p_variante?: string }
        Returns: {
          colores: string[]
          nombre: string
          opciones: string[]
          paquete_id: string
          piezas: string[]
          sale: boolean
        }[]
      }
      catalogo_casos_calcular: {
        Args: { p_version: string }
        Returns: {
          caso_id: string
          nombre: string
          resultado: Json
        }[]
      }
      catalogo_condicion_evaluar: {
        Args: { p_n: Json; p_v: Json }
        Returns: boolean
      }
      catalogo_costos_cargar: {
        Args: { p_confirmar_rojo?: boolean; p_filas: Json }
        Returns: number
      }
      catalogo_costos_niveles: {
        Args: { p_filas: Json }
        Returns: {
          anterior: number | null
          anterior_moneda: Database["public"]["Enums"]["moneda"] | null
          costo: number
          moneda: Database["public"]["Enums"]["moneda"]
          nivel: string | null
          variante_id: string
        }[]
      }
      catalogo_costos_vigentes: {
        Args: { p_en?: string }
        Returns: {
          activo: boolean
          costo: number
          creado_por: string
          created_at: string
          id: string
          moneda: Database["public"]["Enums"]["moneda"]
          updated_at: string
          variante_id: string
        }[]
        SetofOptions: {
          from: "*"
          to: "catalogo_costos"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      catalogo_despiece: {
        Args: { p_entrada?: Json; p_version: string }
        Returns: Json
      }
      catalogo_despiece_elegir: {
        Args: { p_elegidas: Json; p_faltan: string[]; p_m: Json; p_v: Json }
        Returns: Json
      }
      catalogo_despiece_entrada: {
        Args: { p_entrada: Json; p_version: string }
        Returns: {
          adentro: string[]
          color: Json
          elegidas: Json
          errores: string[]
          faltan: string[]
        }[]
      }
      catalogo_despiece_fila: {
        Args: {
          p_cant_pieza: number
          p_color: Json
          p_m: Json
          p_o: Json
          p_v: Json
        }
        Returns: Json
      }
      catalogo_despiece_medida: {
        Args: { p_arbol: Json; p_que: string; p_unidad?: string; p_v: Json }
        Returns: number
      }
      catalogo_despiece_sumas: {
        Args: { p_cant: Json; p_hechos: Json; p_materiales: Json; p_piezas: Json }
        Returns: Json
      }
      catalogo_eleccion_evaluar: {
        Args: { p_n: Json; p_v: Json }
        Returns: string
      }
      catalogo_entrada_valida: { Args: { p_entrada: Json }; Returns: boolean }
      catalogo_fijo_alta: {
        Args: {
          p_categoria: string
          p_costo: number
          p_moneda: Database["public"]["Enums"]["moneda"]
          p_nombre: string
          p_unidad: Database["public"]["Enums"]["unidad_insumo"]
        }
        Returns: string
      }
      catalogo_formula_aritmetica: {
        Args: { p_i: number; p_t: string[] }
        Returns: Json
      }
      catalogo_formula_comparacion: {
        Args: { p_i: number; p_t: string[] }
        Returns: Json
      }
      catalogo_formula_condicion: {
        Args: { p_i: number; p_t: string[] }
        Returns: Json
      }
      catalogo_formula_evaluar: {
        Args: { p_n: Json; p_v: Json }
        Returns: number
      }
      catalogo_formula_expresion: {
        Args: { p_eleccion?: boolean; p_i: number; p_t: string[] }
        Returns: Json
      }
      catalogo_formula_factor: {
        Args: { p_i: number; p_t: string[] }
        Returns: Json
      }
      catalogo_formula_parsear: {
        Args: { p_texto: string; p_tipo?: string }
        Returns: Json
      }
      catalogo_formula_termino: {
        Args: { p_i: number; p_t: string[] }
        Returns: Json
      }
      catalogo_formula_tokens: { Args: { p_texto: string }; Returns: string[] }
      catalogo_formula_usa: { Args: { p_arbol: Json }; Returns: string[] }
      catalogo_insumo_alta: {
        Args: {
          p_categoria: string
          p_colores?: string[]
          p_espesor: number | null
          p_nombre: string
          p_peso: number | null
          p_unidad: Database["public"]["Enums"]["unidad_insumo"]
        }
        Returns: string
      }
      catalogo_numero_texto: { Args: { p_n: number }; Returns: string }
      catalogo_oferta: {
        Args: {
          p_sin_insumo?: string
          p_sin_variante?: string
          p_version: string
        }
        Returns: {
          armable: boolean
          color: string | null
          color_id: string | null
          faltan: string[]
          opciones_fuera: string[]
          piezas_fuera: string[]
        }[]
      }
      catalogo_paquete_alta: {
        Args: { p_categoria: string; p_nombre: string }
        Returns: string
      }
      catalogo_paquete_duplicar: {
        Args: { p_nombre: string; p_version: string }
        Returns: string
      }
      catalogo_porcentaje_activar: {
        Args: { p_activo: boolean; p_id: string }
        Returns: undefined
      }
      catalogo_porcentaje_empezar: { Args: never; Returns: undefined }
      catalogo_porcentaje_guardar: {
        Args: {
          p_categorias: string[]
          p_confirmar_rojo?: boolean
          p_id: string | null
          p_minimo: number | null
          p_minimo_moneda: Database["public"]["Enums"]["moneda"] | null
          p_minimo_por: Database["public"]["Enums"]["alcance_minimo"] | null
          p_nombre: string
          p_opcional: boolean
          p_paso: number
          p_porcentaje: number
        }
        Returns: string
      }
      catalogo_porcentaje_registrar: {
        Args: {
          p_confirmar_rojo?: boolean
          p_v: Database["public"]["Tables"]["catalogo_porcentajes_valores"]["Row"]
        }
        Returns: string
      }
      catalogo_porcentaje_revertir: {
        Args: { p_confirmar_rojo?: boolean; p_valor_id: string }
        Returns: string
      }
      catalogo_porcentajes_historia: {
        Args: { p_id: string }
        Returns: {
          cargado_por: string
          categorias: string[]
          created_at: string
          de_baja: boolean
          id: string
          minimo: number | null
          minimo_moneda: Database["public"]["Enums"]["moneda"] | null
          minimo_por: Database["public"]["Enums"]["alcance_minimo"] | null
          nivel: string | null
          nombre: string
          opcional: boolean
          paso: number
          porcentaje: number
          revierte_id: string | null
          ultimo: boolean
        }[]
      }
      catalogo_porcentajes_vigentes: {
        Args: { p_en?: string }
        Returns: {
          activo: boolean
          categorias: string[]
          creado_por: string
          created_at: string
          de_baja: boolean
          id: string
          minimo: number | null
          minimo_moneda: Database["public"]["Enums"]["moneda"] | null
          minimo_por: Database["public"]["Enums"]["alcance_minimo"] | null
          nombre: string
          opcional: boolean
          paso: number
          porcentaje: number
          porcentaje_id: string
          revierte_id: string | null
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "catalogo_porcentajes_valores"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      catalogo_precio: {
        Args: {
          p_entrada?: Json
          p_moneda?: Database["public"]["Enums"]["moneda"]
          p_opcionales?: string[]
          p_paquete: string
        }
        Returns: Json
      }
      catalogo_precio_calcular: {
        Args: {
          p_en: string
          p_entrada: Json
          p_moneda: Database["public"]["Enums"]["moneda"]
          p_opcionales: string[]
          p_version: string
        }
        Returns: Json
      }
      catalogo_precio_convertir: {
        Args: {
          p_a: Database["public"]["Enums"]["moneda"]
          p_de: Database["public"]["Enums"]["moneda"]
          p_en: string
          p_monto: number
        }
        Returns: number
      }
      catalogo_precio_detalle: {
        Args: {
          p_en?: string
          p_entrada?: Json
          p_moneda?: Database["public"]["Enums"]["moneda"]
          p_opcionales?: string[]
          p_version: string
        }
        Returns: Json
      }
      catalogo_precio_minimos: {
        Args: {
          p_items: Json
          p_moneda?: Database["public"]["Enums"]["moneda"]
        }
        Returns: {
          monto: number
          nombre: string
          porcentaje_id: string
        }[]
      }
      catalogo_precio_redondear: {
        Args: {
          p_moneda: Database["public"]["Enums"]["moneda"]
          p_monto: number
        }
        Returns: number
      }
      catalogo_precio_venta: {
        Args: {
          p_entrada: Json
          p_moneda: Database["public"]["Enums"]["moneda"]
          p_opcionales: string[]
          p_paquete: string
        }
        Returns: Json
      }
      catalogo_precios_referencia: {
        Args: {
          p_desde?: string
          p_hasta?: string
          p_moneda?: Database["public"]["Enums"]["moneda"]
        }
        Returns: {
          cambio: number | null
          caso: string
          caso_id: string
          nombre: string
          numero: number
          paquete_id: string
          precio_desde: number | null
          precio_hasta: number | null
          sin_precio_desde: string[]
          sin_precio_hasta: string[]
          version_id: string
        }[]
      }
      catalogo_puede_editar: {
        Args: { p_tipo: Database["public"]["Enums"]["tipo_catalogo"] }
        Returns: boolean
      }
      catalogo_puede_ver: { Args: never; Returns: boolean }
      catalogo_tipos_con_costo: {
        Args: never
        Returns: Database["public"]["Enums"]["tipo_catalogo"][]
      }
      catalogo_variante_sumar: {
        Args: { p_color: string | null; p_insumo: string }
        Returns: string
      }
      catalogo_version_alcance: {
        Args: { p_version: string }
        Returns: {
          desde: string | null
          llega: string
        }[]
      }
      catalogo_version_aprobar: {
        Args: { p_version: string }
        Returns: undefined
      }
      catalogo_version_bloquear: {
        Args: { p_version: string }
        Returns: undefined
      }
      catalogo_version_circular: {
        Args: { p_version: string }
        Returns: string
      }
      catalogo_version_copiar: {
        Args: { p_nombre: string; p_origen: string; p_paquete: string }
        Returns: string
      }
      catalogo_version_descartar: {
        Args: { p_version: string }
        Returns: undefined
      }
      catalogo_version_devolver: {
        Args: { p_motivo: string; p_version: string }
        Returns: undefined
      }
      catalogo_version_enviar: {
        Args: { p_version: string }
        Returns: undefined
      }
      catalogo_version_exigir: {
        Args: { p_version: string }
        Returns: undefined
      }
      catalogo_version_formulas: {
        Args: { p_version: string }
        Returns: {
          arbol: Json
          nodo: string | null
          pieza_id: string | null
          quien: string
        }[]
      }
      catalogo_version_frena: {
        Args: { p_version: string }
        Returns: string[]
      }
      catalogo_version_insumos: {
        Args: { p_version: string }
        Returns: {
          activo: boolean
          con_alto: boolean
          con_ancho: boolean
          con_area: boolean
          con_color: boolean
          con_medida: boolean
          cuenta_espesor: boolean
          cuenta_peso: boolean
          espesor: number | null
          insumo: string
          insumo_id: string
          material: string
          peso: number | null
          pieza: string
          tipo: Database["public"]["Enums"]["tipo_catalogo"]
          unidad: Database["public"]["Enums"]["unidad_insumo"]
        }[]
      }
      catalogo_version_nueva: {
        Args: { p_origen?: string; p_paquete: string }
        Returns: string
      }
      catalogo_version_oferta: {
        Args: { p_version: string }
        Returns: {
          armable: boolean
          color: string | null
          color_id: string | null
          faltan: string[]
          opciones_fuera: string[]
          piezas_fuera: string[]
        }[]
      }
      catalogo_version_referencias: {
        Args: { p_version: string }
        Returns: {
          hacia: string[] | null
          nodo: string | null
          problema: string | null
          quien: string
        }[]
      }
      catalogo_version_registrar: {
        Args: {
          p_accion: Database["public"]["Enums"]["accion_version_catalogo"]
          p_estado: Database["public"]["Enums"]["estado_version_catalogo"]
          p_motivo?: string
          p_version: string
        }
        Returns: undefined
      }
      catalogo_version_retirar: {
        Args: { p_version: string }
        Returns: undefined
      }
      catalogo_version_revisar: {
        Args: { p_version: string }
        Returns: string[]
      }
      catalogo_version_tomar: {
        Args: {
          p_estado: Database["public"]["Enums"]["estado_version_catalogo"]
          p_permiso: string
          p_version: string
        }
        Returns: Database["public"]["Tables"]["catalogo_versiones"]["Row"]
      }
      contactos_auditoria_detalle: {
        Args: { p_dias: number; p_persona?: string; p_usuario?: string }
        Returns: {
          created_at: string
          dueno: string
          dueno_id: string
          persona: string
          persona_id: string
          usuario: string
          usuario_id: string
        }[]
      }
      contactos_auditoria_personas: {
        Args: { p_texto: string }
        Returns: {
          id: string
          nombre: string
        }[]
      }
      contactos_auditoria_resumen: {
        Args: { p_dias: number }
        Returns: {
          accesos: number
          personas: number
          usuario: string
          usuario_id: string
        }[]
      }
      contactos_avisar_huerfanas: {
        Args: { p_usuario: string }
        Returns: undefined
      }
      contactos_buscar: {
        Args: { p_texto: string }
        Returns: {
          id: string
          subtitulo: string
          tipo: string
          titulo: string
        }[]
      }
      contactos_compartir_empresa: {
        Args: { p_compartir: boolean; p_empresa: string; p_equipo: string }
        Returns: undefined
      }
      contactos_congelado: {
        Args: { p_empresa: string; p_persona: string }
        Returns: string
      }
      contactos_crear_guardados: { Args: { p_id: string }; Returns: undefined }
      contactos_crear_y_vincular: {
        Args: {
          p_cargo?: string
          p_email?: string
          p_empresa_id?: string
          p_empresa_nombre?: string
          p_ente: string
          p_nombre: string
          p_registro: string
          p_roles: string[]
          p_telefono?: string
          p_tipo: string
        }
        Returns: string
      }
      contactos_desactivar_empresa: {
        Args: { p_empresa: string }
        Returns: undefined
      }
      contactos_desactivar_persona: {
        Args: { p_persona: string }
        Returns: undefined
      }
      contactos_desactivar_persona_empresa: {
        Args: { p_relacion: string }
        Returns: undefined
      }
      contactos_desactivar_vinculo: {
        Args: { p_vinculo: string }
        Returns: undefined
      }
      contactos_descartar_guardados: {
        Args: { p_id: string }
        Returns: undefined
      }
      contactos_empresa_de_mi_equipo: {
        Args: { p_creado_por: string; p_empresa: string; p_equipo: string }
        Returns: boolean
      }
      contactos_empresa_del_equipo_de: {
        Args: {
          p_creado_por: string
          p_empresa: string
          p_equipo: string
          p_usuario: string
        }
        Returns: boolean
      }
      contactos_empresas_parecidas_de: {
        Args: { p_empresa: string; p_nombre: string }
        Returns: {
          id: string
        }[]
      }
      contactos_entregar: {
        Args: { p_equipo: string; p_usuario: string }
        Returns: undefined
      }
      contactos_equipos: {
        Args: never
        Returns: {
          id: string
          nombre: string
        }[]
      }
      contactos_etiqueta: {
        Args: { p_id: string; p_tipo: string }
        Returns: string
      }
      contactos_fusion_avisos: {
        Args: never
        Returns: {
          destino: string
          destino_id: string
          etiqueta: string
          motivo: string
          notificacion_id: string
        }[]
      }
      contactos_fusionada: {
        Args: { p_id: string; p_tipo: string }
        Returns: {
          dueno: string
          id: string
          nombre: string
        }[]
      }
      contactos_fusionar: {
        Args: {
          p_conservar?: string[]
          p_email_de_la_otra?: boolean
          p_queda: string
          p_se_va: string
          p_telefono_de_la_otra?: boolean
          p_tipo: string
        }
        Returns: undefined
      }
      contactos_historial_contacto: {
        Args: { p_persona: string }
        Returns: {
          actor_id: string
          anterior: string
          campo: string
          created_at: string
          nuevo: string
        }[]
      }
      contactos_jefe_de: { Args: { p_equipo: string }; Returns: string }
      contactos_nombres: {
        Args: never
        Returns: {
          id: string
          nombre: string
        }[]
      }
      contactos_parecidas: {
        Args: {
          p_email?: string
          p_id?: string
          p_nombre: string
          p_telefono?: string
          p_tipo: string
        }
        Returns: {
          coincide: string[]
          dueno: string
          equipo: string
          id: string
          nombre: string
        }[]
      }
      contactos_personas_parecidas_de: {
        Args: {
          p_email: string
          p_nombre: string
          p_persona: string
          p_telefono: string
        }
        Returns: {
          coincide: string[]
          id: string
        }[]
      }
      contactos_por_aprobar: {
        Args: never
        Returns: {
          antes: Json
          created_at: string
          dueno: string
          equipo: string
          guardados: Json
          id: string
          nombre: string
          notas: string
          parecidas: Json
          tipo: string
        }[]
      }
      contactos_puede_abrir: {
        Args: { p_id: string; p_tipo: string; p_usuario: string }
        Returns: boolean
      }
      contactos_puede_ver_empresa: {
        Args: {
          p_activo: boolean
          p_creado_por: string
          p_empresa: string
          p_equipo: string
        }
        Returns: boolean
      }
      contactos_puede_ver_empresa_de: {
        Args: {
          p_activo: boolean
          p_creado_por: string
          p_empresa: string
          p_equipo: string
          p_usuario: string
        }
        Returns: boolean
      }
      contactos_puede_ver_persona: {
        Args: { p_activo: boolean; p_persona: string; p_responsable: string }
        Returns: boolean
      }
      contactos_puede_ver_persona_de: {
        Args: {
          p_activo: boolean
          p_persona: string
          p_responsable: string
          p_usuario: string
        }
        Returns: boolean
      }
      contactos_puede_ver_relacion: {
        Args: { p_contacto: string; p_ente: string; p_id: string }
        Returns: boolean
      }
      contactos_registrar_acceso: {
        Args: { p_persona: string }
        Returns: undefined
      }
      contactos_relacionados: {
        Args: { p_ente: string; p_id: string }
        Returns: {
          ente: string
          registro_id: string
          rol: string
        }[]
      }
      contactos_resolver: {
        Args: {
          p_decision: string
          p_existente?: string
          p_id: string
          p_motivo?: string
          p_tipo: string
          p_vincular?: boolean
        }
        Returns: undefined
      }
      contactos_transferir_persona: {
        Args: { p_persona: string; p_responsable: string }
        Returns: undefined
      }
      contactos_ver_contacto: {
        Args: { p_persona: string }
        Returns: {
          email: string
          telefono: string
        }[]
      }
      contactos_vinculables: {
        Args: { p_texto: string }
        Returns: {
          detalle: string
          id: string
          nombre: string
          tipo: string
        }[]
      }
      copiar_plantilla: { Args: { p_plantilla: string }; Returns: string }
      delegar_submodulos: {
        Args: { p_submodulos: string[]; p_usuario: string }
        Returns: undefined
      }
      designar_delegador: {
        Args: { p_admin: string; p_usuario: string }
        Returns: undefined
      }
      duplicados_avisos: {
        Args: never
        Returns: {
          destino: string
          destino_id: string
          etiqueta: string
          motivo: string
          notificacion_id: string
        }[]
      }
      emitir_evento: {
        Args: {
          p_detalle?: Json
          p_ente: string
          p_evento: Database["public"]["Enums"]["tipo_evento"]
          p_registro_id: string
        }
        Returns: undefined
      }
      equipo_de: { Args: { p_usuario: string }; Returns: string }
      etiqueta_registro: {
        Args: { p_ente: string; p_id: string }
        Returns: string
      }
      etiqueta_registro_de: {
        Args: { p_ente: string; p_id: string; p_usuario: string }
        Returns: string
      }
      fijar_delegables: {
        Args: { p_admin: string; p_submodulos: string[] }
        Returns: undefined
      }
      guardar_plantilla: {
        Args: {
          p_descripcion: string
          p_disparo_activo?: boolean
          p_disparo_estado?: string
          p_disparo_evento?: Database["public"]["Enums"]["tipo_evento"]
          p_id: string
          p_nombre: string
          p_pasos: Json
          p_sobre?: string
        }
        Returns: string
      }
      mi_equipo: { Args: never; Returns: string }
      monedas_avisos: {
        Args: never
        Returns: {
          aviso: string
          desde: string
          moneda: Database["public"]["Enums"]["moneda"]
          valor: number
        }[]
      }
      monedas_cerrar_consulta: {
        Args: { p_error: string; p_id: string }
        Returns: undefined
      }
      monedas_confirmar: { Args: { p_id: string }; Returns: undefined }
      monedas_convertir: {
        Args: {
          p_a: Database["public"]["Enums"]["moneda"]
          p_de: Database["public"]["Enums"]["moneda"]
          p_en?: string
          p_monto: number
        }
        Returns: number
      }
      monedas_corregir: {
        Args: {
          p_confirmar_rojo?: boolean
          p_moneda: Database["public"]["Enums"]["moneda"]
          p_valor: number
        }
        Returns: string
      }
      monedas_elegir_principal: {
        Args: { p_moneda: Database["public"]["Enums"]["moneda"] }
        Returns: undefined
      }
      monedas_formato: { Args: { p_valor: number }; Returns: string }
      monedas_guardar_monedapi: {
        Args: {
          p_fecha: string
          p_moneda: Database["public"]["Enums"]["moneda"]
          p_valor: number
        }
        Returns: string
      }
      monedas_historial: {
        Args: {
          p_limite?: number
          p_moneda: Database["public"]["Enums"]["moneda"]
        }
        Returns: {
          activo: boolean
          anterior: number
          cargado_por: string
          confirmado_por: string
          fecha: string
          id: string
          nivel: string
          origen: Database["public"]["Enums"]["origen_tipo_cambio"]
          valor: number
          vigente_desde: string
        }[]
      }
      monedas_hoy: {
        Args: never
        Returns: {
          fecha: string
          moneda: Database["public"]["Enums"]["moneda"]
          ultima_consulta: string
          valor: number
        }[]
      }
      monedas_principal_actual: {
        Args: never
        Returns: Database["public"]["Enums"]["moneda"]
      }
      monedas_reservar_consulta: {
        Args: { p_forzada: boolean }
        Returns: string
      }
      monedas_tipo_cambio: {
        Args: {
          p_en?: string
          p_moneda: Database["public"]["Enums"]["moneda"]
        }
        Returns: number
      }
      nivel_cambio: {
        Args: { p_anterior: number; p_nuevo: number }
        Returns: string
      }
      normalizar_telefono: { Args: { t: string }; Returns: string }
      normalizar_texto: { Args: { p: string }; Returns: string }
      notificaciones_actores: {
        Args: never
        Returns: {
          id: string
          nombre: string
        }[]
      }
      notificaciones_listar: {
        Args: { p_limite?: number }
        Returns: {
          actor: string
          created_at: string
          destino: string
          destino_id: string
          etiqueta: string
          id: string
          leida: boolean
          motivo: string
          tipo: Database["public"]["Enums"]["tipo_notificacion"]
        }[]
      }
      notificar: {
        Args: {
          p_actor_id: string
          p_entidad: string
          p_entidad_id: string
          p_tipo: Database["public"]["Enums"]["tipo_notificacion"]
          p_usuario_id: string
        }
        Returns: undefined
      }
      numeros_de: { Args: { p: string }; Returns: string[] }
      obras_a_cargo: { Args: { p_obra: string }; Returns: boolean }
      obras_a_cargo_de: {
        Args: { p_obra: string; p_usuario: string }
        Returns: boolean
      }
      obras_alta: {
        Args: {
          p_compra_estimada?: string
          p_direccion: string
          p_estado?: Database["public"]["Enums"]["estado_obra"]
          p_localidad?: string
          p_nombre: string
          p_notas?: string
          p_origen: Database["public"]["Enums"]["origen_obra"]
          p_quien_empresa?: string
          p_quien_nuevo_email?: string
          p_quien_nuevo_nombre?: string
          p_quien_nuevo_telefono?: string
          p_quien_nuevo_tipo?: string
          p_quien_persona?: string
          p_tipo: Database["public"]["Enums"]["tipo_obra"]
        }
        Returns: string
      }
      obras_avisar_huerfanas: {
        Args: { p_usuario: string }
        Returns: undefined
      }
      obras_avisos_salida: {
        Args: never
        Returns: {
          nombre: string
          notificacion_id: string
          obra_id: string
        }[]
      }
      obras_buscar: {
        Args: { p_texto: string }
        Returns: {
          id: string
          subtitulo: string
          tipo: string
          titulo: string
        }[]
      }
      obras_congelada: { Args: { p_obra: string }; Returns: string }
      obras_contar: {
        Args: { p_dias: number }
        Returns: {
          cantidad: number
          clave: string
          grupo: string
        }[]
      }
      obras_desactivar: { Args: { p_obra: string }; Returns: undefined }
      obras_entregar: { Args: { p_usuario: string }; Returns: undefined }
      obras_etiqueta: {
        Args: { p_id: string; p_tipo: string }
        Returns: string
      }
      obras_jefe_de: { Args: { p_equipo: string }; Returns: string }
      obras_nombres: {
        Args: never
        Returns: {
          id: string
          nombre: string
        }[]
      }
      obras_parecidas: {
        Args: { p_direccion: string; p_nombre: string; p_obra?: string }
        Returns: {
          direccion: string
          id: string
          nombre: string
          responsable: string
        }[]
      }
      obras_parecidas_de: {
        Args: { p_direccion: string; p_nombre: string; p_obra: string }
        Returns: {
          coincide: string
          id: string
        }[]
      }
      obras_por_aprobar: {
        Args: never
        Returns: {
          antes: Json
          created_at: string
          direccion: string
          estado: Database["public"]["Enums"]["estado_obra"]
          guardados: Json
          id: string
          localidad: string
          nombre: string
          notas: string
          origen: Database["public"]["Enums"]["origen_obra"]
          parecidas: Json
          responsable: string
          tipo: Database["public"]["Enums"]["tipo_obra"]
        }[]
      }
      obras_puede_abrir: {
        Args: { p_id: string; p_tipo: string; p_usuario: string }
        Returns: boolean
      }
      obras_puede_ver_obra: {
        Args: {
          p_activo: boolean
          p_equipo: string
          p_obra: string
          p_responsable: string
        }
        Returns: boolean
      }
      obras_puede_ver_obra_de: {
        Args: {
          p_activo: boolean
          p_equipo: string
          p_obra: string
          p_responsable: string
          p_usuario: string
        }
        Returns: boolean
      }
      obras_registrar_comision: {
        Args: {
          p_moneda?: Database["public"]["Enums"]["moneda"]
          p_monto: number
          p_porcentaje: number
          p_vinculo: string
        }
        Returns: string
      }
      obras_resolver: {
        Args: {
          p_decision: string
          p_existente?: string
          p_motivo?: string
          p_obra: string
        }
        Returns: undefined
      }
      obras_trabaja: { Args: { p_obra: string }; Returns: boolean }
      obras_trabaja_de: {
        Args: { p_obra: string; p_usuario: string }
        Returns: boolean
      }
      obras_transferir: {
        Args: { p_obra: string; p_quedarme?: boolean; p_responsable: string }
        Returns: undefined
      }
      obras_ve_comision: { Args: { p_vinculo: string }; Returns: boolean }
      puede_abrir_registro: {
        Args: { p_ente: string; p_id: string; p_usuario: string }
        Returns: boolean
      }
      puede_ver_relacion: {
        Args: {
          p_ente: string
          p_ente_rel: string
          p_id: string
          p_id_rel: string
        }
        Returns: boolean
      }
      quitar_delegador: {
        Args: {
          p_admin: string
          p_heredero: string | null
          p_no_copiar?: string[]
          p_saliente: string
        }
        Returns: undefined
      }
      relacionados_de_registro: {
        Args: { p_ente: string; p_id: string }
        Returns: {
          ente: string
          registro_id: string
          rol: string
        }[]
      }
      relacionados_de_registro_de: {
        Args: { p_ente: string; p_id: string; p_usuario: string }
        Returns: {
          ente: string
          registro_id: string
          rol: string
        }[]
      }
      registro_congelado: {
        Args: { p_ente: string; p_id: string }
        Returns: string
      }
      tareas_actua_como_asignado: {
        Args: { p_actor: string; p_equipo: string; p_usuario: string }
        Returns: boolean
      }
      tareas_asignables: {
        Args: never
        Returns: {
          equipo_id: string
          nombre: string
          pedido: boolean
          puede_recibir: boolean
          usuario_id: string
        }[]
      }
      tareas_avisar_asignado: {
        Args: { p: Database["public"]["Tables"]["tareas"]["Row"] }
        Returns: undefined
      }
      tareas_avisar_huerfanos: {
        Args: { p_usuario: string }
        Returns: undefined
      }
      tareas_avisos_salida: {
        Args: never
        Returns: {
          notificacion_id: string
          titulo: string
        }[]
      }
      tareas_bloquea: { Args: { p_paso: string }; Returns: boolean }
      tareas_buscar: {
        Args: { p_texto: string }
        Returns: {
          id: string
          subtitulo: string
          tipo: string
          titulo: string
        }[]
      }
      tareas_cancelar_y_cerrar: {
        Args: { p_generar?: boolean; p_hilo: string; p_resultado?: string }
        Returns: undefined
      }
      tareas_completar_con_nota: {
        Args: { p_nota: string; p_resultado?: string; p_tarea: string }
        Returns: undefined
      }
      tareas_delegador_de: { Args: { p_equipo: string }; Returns: string }
      tareas_desactivar_hilo: { Args: { p_hilo: string }; Returns: undefined }
      tareas_desactivar_paso: { Args: { p_paso: string }; Returns: undefined }
      tareas_destinatario: {
        Args: { p_equipo: string; p_usuario: string }
        Returns: string
      }
      tareas_entregar: { Args: { p_usuario: string }; Returns: undefined }
      tareas_equipo_de_asignado: {
        Args: { p_equipo: string; p_usuario: string }
        Returns: string
      }
      tareas_es_pedido: {
        Args: { p_equipo: string; p_responsable: string; p_usuario: string }
        Returns: boolean
      }
      tareas_estado_al_abrir: {
        Args: {
          p_directo: boolean
          p_equipo: string
          p_responsable: string
          p_usuario: string
        }
        Returns: Database["public"]["Enums"]["estado_tarea"]
      }
      tareas_etiqueta: {
        Args: { p_id: string; p_tipo: string }
        Returns: string
      }
      tareas_hoy: { Args: never; Returns: string }
      tareas_insertar_antes: {
        Args: {
          p_asignado_equipo_id: string
          p_asignado_id: string
          p_descripcion: string
          p_prioridad?: Database["public"]["Enums"]["prioridad_tarea"]
          p_siguiente: string
          p_titulo: string
          p_vence?: string
          p_vence_dias?: number
        }
        Returns: string
      }
      tareas_nombres: {
        Args: never
        Returns: {
          id: string
          nombre: string
        }[]
      }
      tareas_puede_recibir: {
        Args: { p_equipo: string; p_usuario: string }
        Returns: boolean
      }
      tareas_puede_ver_hilo: {
        Args: {
          p_activo: boolean
          p_equipo: string
          p_hilo: string
          p_responsable: string
        }
        Returns: boolean
      }
      tareas_puede_ver_hilo_de: {
        Args: {
          p_activo: boolean
          p_equipo: string
          p_hilo: string
          p_responsable: string
          p_usuario: string
        }
        Returns: boolean
      }
      tareas_puede_ver_plantilla: {
        Args: {
          p_activo: boolean
          p_dueno: string
          p_publicada: boolean
          p_sobre: string
        }
        Returns: boolean
      }
      tareas_puede_ver_tarea: {
        Args: { p_activo: boolean; p_hilo: string }
        Returns: boolean
      }
      tareas_puede_ver_tarea_de: {
        Args: { p_activo: boolean; p_hilo: string; p_usuario: string }
        Returns: boolean
      }
      tareas_referencias: {
        Args: { p_texto: string }
        Returns: {
          ente: string
          registro_id: string
        }[]
      }
      tareas_siguiente_efectivo: { Args: { p_paso: string }; Returns: string }
      tareas_transferir_hilo: {
        Args: { p_hilo: string; p_responsable: string }
        Returns: undefined
      }
      tiene_permiso: { Args: { p_codigo: string }; Returns: boolean }
      trabaja_registro: {
        Args: { p_ente: string; p_id: string }
        Returns: boolean
      }
      trabaja_registro_de: {
        Args: { p_ente: string; p_id: string; p_usuario: string }
        Returns: boolean
      }
      usar_plantilla: {
        Args: {
          p_asignados?: Json
          p_hilo?: string
          p_plantilla: string
          p_registro?: string
          p_titulo?: string
        }
        Returns: string
      }
      usuario_tiene_permiso: {
        Args: { p_codigo: string; p_usuario: string }
        Returns: boolean
      }
      usuarios_con_permiso: {
        Args: { p_codigo: string }
        Returns: {
          id: string
          nombre: string
        }[]
      }
    }
    Enums: {
      accion_version_catalogo:
        | "enviada"
        | "retirada"
        | "devuelta"
        | "aprobada"
        | "obsoleta"
        | "descartada"
      alcance_minimo: "paquete" | "presupuesto"
      estado_hilo: "abierto" | "cerrado"
      estado_obra:
        | "idea"
        | "en_busqueda"
        | "en_cotizacion"
        | "contratada"
        | "perdida"
      estado_tarea:
        | "solicitada"
        | "pendiente"
        | "rechazada"
        | "completada"
        | "cancelada"
      estado_version_catalogo:
        | "borrador"
        | "en_revision"
        | "publicado"
        | "obsoleto"
        | "descartado"
      moneda: "ARS" | "USD_OFICIAL" | "USD_BLUE" | "EUR"
      motivo_perdida:
        | "precio"
        | "plazo"
        | "producto"
        | "proveedor_habitual"
        | "obra_suspendida"
        | "sin_respuesta"
        | "otro"
      origen_obra:
        | "referente"
        | "cartel"
        | "web_redes"
        | "cliente_anterior"
        | "llamado"
        | "otro"
      origen_tipo_cambio: "monedapi" | "manual"
      prioridad_tarea: "baja" | "media" | "alta"
      recurrencia_unidad: "dia" | "mes"
      tipo_catalogo: "paquete" | "insumo" | "servicio"
      tipo_evento:
        | "alta"
        | "baja"
        | "reactivacion"
        | "estado"
        | "relacion_alta"
        | "relacion_baja"
        | "transferencia"
      tipo_material: "unico" | "elige_vendedor" | "elige_sistema" | "sigue"
      tipo_notificacion:
        | "miembro_nuevo"
        | "permiso_otorgado"
        | "delegador_designado"
        | "tarea_asignada"
        | "pedido_recibido"
        | "paso_editado"
        | "pedido_aceptado"
        | "pedido_rechazado"
        | "paso_reabierto"
        | "hilo_transferido"
        | "paso_habilitado"
        | "paso_bloqueado"
        | "paso_reasignado"
        | "paso_quitado"
        | "paso_a_reasignar"
        | "paso_sumado"
        | "paso_huerfano"
        | "hilos_huerfanos"
        | "hilo_dado_de_baja"
        | "paso_dado_de_baja"
        | "paso_completado"
        | "paso_cancelado"
        | "obra_transferida"
        | "obra_sumado"
        | "obra_quitado"
        | "obras_recibidas"
        | "obras_huerfanas"
        | "persona_transferida"
        | "agenda_recibida"
        | "personas_huerfanas"
        | "alta_por_aprobar"
        | "alta_aprobada"
        | "alta_rechazada"
        | "alta_es_la_misma"
        | "obra_misma_sumado"
        | "persona_fusionada"
        | "plantilla_disparada"
        | "plantilla_fallida"
        | "tipo_cambio_corregido"
        | "tipo_cambio_confirmado"
      tipo_obra:
        | "edificio_residencial"
        | "casa"
        | "oficinas_comercial"
        | "industrial"
        | "otro"
      tipo_regla_submodulo: "requiere" | "excluye"
      tipo_submodulo: "vista" | "funcion"
      unidad_insumo: "mm" | "m2" | "u"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      accion_version_catalogo: [
        "enviada",
        "retirada",
        "devuelta",
        "aprobada",
        "obsoleta",
        "descartada",
      ],
      alcance_minimo: ["paquete", "presupuesto"],
      estado_hilo: ["abierto", "cerrado"],
      estado_obra: [
        "idea",
        "en_busqueda",
        "en_cotizacion",
        "contratada",
        "perdida",
      ],
      estado_tarea: [
        "solicitada",
        "pendiente",
        "rechazada",
        "completada",
        "cancelada",
      ],
      estado_version_catalogo: [
        "borrador",
        "en_revision",
        "publicado",
        "obsoleto",
        "descartado",
      ],
      moneda: ["ARS", "USD_OFICIAL", "USD_BLUE", "EUR"],
      motivo_perdida: [
        "precio",
        "plazo",
        "producto",
        "proveedor_habitual",
        "obra_suspendida",
        "sin_respuesta",
        "otro",
      ],
      origen_obra: [
        "referente",
        "cartel",
        "web_redes",
        "cliente_anterior",
        "llamado",
        "otro",
      ],
      origen_tipo_cambio: ["monedapi", "manual"],
      prioridad_tarea: ["baja", "media", "alta"],
      recurrencia_unidad: ["dia", "mes"],
      tipo_catalogo: ["paquete", "insumo", "servicio"],
      tipo_evento: [
        "alta",
        "baja",
        "reactivacion",
        "estado",
        "relacion_alta",
        "relacion_baja",
        "transferencia",
      ],
      tipo_material: ["unico", "elige_vendedor", "elige_sistema", "sigue"],
      tipo_notificacion: [
        "miembro_nuevo",
        "permiso_otorgado",
        "delegador_designado",
        "tarea_asignada",
        "pedido_recibido",
        "paso_editado",
        "pedido_aceptado",
        "pedido_rechazado",
        "paso_reabierto",
        "hilo_transferido",
        "paso_habilitado",
        "paso_bloqueado",
        "paso_reasignado",
        "paso_quitado",
        "paso_a_reasignar",
        "paso_sumado",
        "paso_huerfano",
        "hilos_huerfanos",
        "hilo_dado_de_baja",
        "paso_dado_de_baja",
        "paso_completado",
        "paso_cancelado",
        "obra_transferida",
        "obra_sumado",
        "obra_quitado",
        "obras_recibidas",
        "obras_huerfanas",
        "persona_transferida",
        "agenda_recibida",
        "personas_huerfanas",
        "alta_por_aprobar",
        "alta_aprobada",
        "alta_rechazada",
        "alta_es_la_misma",
        "obra_misma_sumado",
        "persona_fusionada",
        "plantilla_disparada",
        "plantilla_fallida",
        "tipo_cambio_corregido",
        "tipo_cambio_confirmado",
      ],
      tipo_obra: [
        "edificio_residencial",
        "casa",
        "oficinas_comercial",
        "industrial",
        "otro",
      ],
      tipo_regla_submodulo: ["requiere", "excluye"],
      tipo_submodulo: ["vista", "funcion"],
      unidad_insumo: ["mm", "m2", "u"],
    },
  },
} as const
