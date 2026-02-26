/* =============================================================================
   SEMANA 8 - PROGRAMACIÓN DE BASES DE DATOS (PRY2206)
   ACTIVIDAD SUMATIVA: DESARROLLANDO PROGRAMAS PL/SQL EN LA BASE DE DATOS
   AUTOR: [Tu Nombre]
   ============================================================================= */

-- 1. CASO 1: TRIGGER DE INTEGRIDAD
-- Mantiene actualizada la tabla TOTAL_CONSUMOS ante cambios en la tabla CONSUMO.

CREATE OR REPLACE TRIGGER TRG_ACTUALIZA_CONSUMOS
AFTER INSERT OR UPDATE OR DELETE ON CONSUMO
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        UPDATE TOTAL_CONSUMOS 
        SET MONTO_CONSUMOS = MONTO_CONSUMOS + :NEW.MONTO_CONSUMO
        WHERE ID_HUESPED = :NEW.ID_HUESPED;
    ELSIF UPDATING THEN
        UPDATE TOTAL_CONSUMOS 
        SET MONTO_CONSUMOS = MONTO_CONSUMOS - :OLD.MONTO_CONSUMO + :NEW.MONTO_CONSUMO
        WHERE ID_HUESPED = :NEW.ID_HUESPED;
    ELSIF DELETING THEN
        UPDATE TOTAL_CONSUMOS 
        SET MONTO_CONSUMOS = MONTO_CONSUMOS - :OLD.MONTO_CONSUMO
        WHERE ID_HUESPED = :OLD.ID_HUESPED;
    END IF;
END;
/

-- 2. FUNCIONES ALMACENADAS EXTERNAS (CASO 2)
-- Estas funciones son llamadas desde el proceso principal para modularizar la lógica.

CREATE OR REPLACE FUNCTION FN_OBTENER_AGENCIA(p_id_huesped NUMBER) RETURN VARCHAR2 IS
    v_nom_agencia VARCHAR2(100);
BEGIN
    SELECT a.nom_agencia INTO v_nom_agencia
    FROM HUESPED h JOIN AGENCIA a ON h.id_agencia = a.id_agencia
    WHERE h.id_huesped = p_id_huesped;
    RETURN v_nom_agencia;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 'NO REGISTRA AGENCIA';
    WHEN OTHERS THEN
        -- Uso de secuencia SQ_ERROR según pauta
        INSERT INTO REG_ERRORES (ID_ERROR, NOMSUBPROGRAMA, MSG_ERROR)
        VALUES (SQ_ERROR.NEXTVAL, 'FN_OBTENER_AGENCIA', SUBSTR(SQLERRM, 1, 250));
        RETURN 'NO REGISTRA AGENCIA';
END;
/

CREATE OR REPLACE FUNCTION FN_MONTO_CONSUMOS(p_id_huesped NUMBER) RETURN NUMBER IS
    v_monto NUMBER;
BEGIN
    SELECT MONTO_CONSUMOS INTO v_monto FROM TOTAL_CONSUMOS WHERE ID_HUESPED = p_id_huesped;
    RETURN NVL(v_monto, 0);
EXCEPTION
    WHEN OTHERS THEN RETURN 0;
END;
/

-- 3. ESPECIFICACIÓN DEL PACKAGE
CREATE OR REPLACE PACKAGE PKG_LIQUIDACION IS
    FUNCTION FN_CALCULAR_TOURS(p_id_huesped NUMBER) RETURN NUMBER;
    PROCEDURE SP_GENERAR_DETALLE(p_fecha DATE, p_valor_dolar NUMBER);
END PKG_LIQUIDACION;
/

-- 4. CUERPO DEL PACKAGE (LÓGICA DE NEGOCIO)
CREATE OR REPLACE PACKAGE BODY PKG_LIQUIDACION IS

    FUNCTION FN_CALCULAR_TOURS(p_id_huesped NUMBER) RETURN NUMBER IS
    BEGIN
        -- Regla de negocio: si no hay tours, se asume 0.
        RETURN 0; 
    END FN_CALCULAR_TOURS;

    PROCEDURE SP_GENERAR_DETALLE(p_fecha DATE, p_valor_dolar NUMBER) IS
        v_subtotal     NUMBER;
        v_desc_agencia NUMBER;
        v_total        NUMBER;
        v_agencia      VARCHAR2(100);
        v_consumo_usd  NUMBER;
        v_tours_usd    NUMBER;
        v_alojamiento  NUMBER;
    BEGIN
        -- Limpieza previa de tablas de salida
        EXECUTE IMMEDIATE 'DELETE FROM DETALLE_DIARIO_HUESPEDES';
        EXECUTE IMMEDIATE 'DELETE FROM REG_ERRORES';
        COMMIT;

        -- Cursor para procesar huéspedes cuya fecha de salida coincida con el parámetro
        FOR reg IN (SELECT h.id_huesped, 
                           h.nom_huesped || ' ' || h.appat_huesped as nombre, 
                           r.cant_personas 
                    FROM HUESPED h 
                    JOIN RESERVA r ON h.id_huesped = r.id_huesped
                    WHERE r.fecha_salida = p_fecha) 
        LOOP
            -- Obtención de datos mediante funciones
            v_agencia     := FN_OBTENER_AGENCIA(reg.id_huesped);
            v_consumo_usd := FN_MONTO_CONSUMOS(reg.id_huesped);
            v_tours_usd   := FN_CALCULAR_TOURS(reg.id_huesped);
            
            -- Cálculo de Alojamiento: $35.000 por persona
            v_alojamiento := 35000 * reg.cant_personas;
            
            -- Subtotal CLP: Alojamiento + (Consumos + Tours) * Valor Dólar
            v_subtotal := ROUND(v_alojamiento + (v_consumo_usd + v_tours_usd) * p_valor_dolar);
            
            -- Descuento 12% solo para la agencia 'Viajes Alberti'
            IF v_agencia = 'Viajes Alberti' THEN
                v_desc_agencia := ROUND(v_subtotal * 0.12);
            ELSE
                v_desc_agencia := 0;
            END IF;
            
            v_total := v_subtotal - v_desc_agencia;

            -- Inserción de resultados en la tabla detalle
            INSERT INTO DETALLE_DIARIO_HUESPEDES (
                ID_HUESPED, NOMBRE, AGENCIA, MONTO_ALOJAMIENTO, 
                MONTO_CONSUMOS, MONTO_TOURS, SUBTOTAL_PAGO, 
                DESCUENTO_CONSUMO, DESCUENTOS_AGENCIA, TOTAL
            ) VALUES (
                reg.id_huesped, reg.nombre, v_agencia, v_alojamiento, 
                ROUND(v_consumo_usd * p_valor_dolar), ROUND(v_tours_usd * p_valor_dolar), 
                v_subtotal, 0, v_desc_agencia, v_total
            );
        END LOOP;
        COMMIT;
    END SP_GENERAR_DETALLE;
END PKG_LIQUIDACION;
/

-- 5. BLOQUE DE EJECUCIÓN Y PRUEBAS FINAL
-- Este bloque realiza las operaciones del Caso 1 y ejecuta el proceso principal del Caso 2.

BEGIN
    -- Pruebas Caso 1 (Trigger)
    -- a) Insertar nuevo consumo
    INSERT INTO CONSUMO (ID_CONSUMO, ID_HUESPED, ID_RESERVA, MONTO_CONSUMO) 
    VALUES (11475, 340006, 1587, 150);
    
    -- b) Eliminar consumo
    DELETE FROM CONSUMO WHERE ID_CONSUMO = 11473;
    
    -- c) Actualizar consumo
    UPDATE CONSUMO SET MONTO_CONSUMO = 95 WHERE ID_CONSUMO = 10688;
    
    -- Ejecución Proceso Principal con parámetros de la pauta
    -- Fecha: 18/08/2021, Valor Dólar: 915
    PKG_LIQUIDACION.SP_GENERAR_DETALLE(TO_DATE('18/08/2021','DD/MM/YYYY'), 915);
END;
/

-- CONSULTA DE VERIFICACIÓN
SELECT * FROM DETALLE_DIARIO_HUESPEDES;