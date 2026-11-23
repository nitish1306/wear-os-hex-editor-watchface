package com.clusterrr.hexeditorwatchface

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.SurfaceHolder
import androidx.core.content.ContextCompat
import androidx.health.services.client.HealthServices
import androidx.health.services.client.PassiveListenerCallback
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.IntervalDataPoint
import androidx.health.services.client.data.PassiveListenerConfig
import androidx.wear.watchface.CanvasType
import androidx.wear.watchface.ComplicationSlot
import androidx.wear.watchface.DrawMode
import androidx.wear.watchface.Renderer
import androidx.wear.watchface.TapEvent
import androidx.wear.watchface.TapType
import androidx.wear.watchface.WatchFace
import androidx.wear.watchface.WatchFaceService
import androidx.wear.watchface.WatchFaceType
import androidx.wear.watchface.WatchState
import androidx.wear.watchface.style.CurrentUserStyleRepository
import java.time.Instant
import java.time.ZonedDateTime
import java.util.Arrays
import java.util.Calendar
import java.util.HashSet
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/**
 * Retro hex editor watch face, built on the modern androidx.wear.watchface API.
 */
class HexWatchFace : WatchFaceService() {
    companion object {
        const val TAG = "hex_watchface"
    }

    override suspend fun createWatchFace(
        surfaceHolder: SurfaceHolder,
        watchState: WatchState,
        complicationSlotsManager: androidx.wear.watchface.ComplicationSlotsManager,
        currentUserStyleRepository: CurrentUserStyleRepository
    ): WatchFace {
        val renderer = HexRenderer(applicationContext, surfaceHolder, currentUserStyleRepository, watchState)
        val watchFace = WatchFace(WatchFaceType.DIGITAL, renderer)
        watchFace.setTapListener(object : WatchFace.TapListener {
            override fun onTapEvent(tapType: Int, tapEvent: TapEvent, complicationSlot: ComplicationSlot?) {
                if (tapType == TapType.DOWN) renderer.onTap()
            }
        })
        return watchFace
    }

    internal class HexRenderer(
        private val appContext: Context,
        surfaceHolder: SurfaceHolder,
        currentUserStyleRepository: CurrentUserStyleRepository,
        watchState: WatchState
    ) : Renderer.CanvasRenderer(
        surfaceHolder,
        currentUserStyleRepository,
        watchState,
        CanvasType.SOFTWARE,
        TimeUnit.SECONDS.toMillis(1),
        false
    ) {
        private val prefs: SharedPreferences
            get() = appContext.getSharedPreferences(appContext.getString(R.string.app_name), Context.MODE_PRIVATE)

        private val calendar = Calendar.getInstance()
        private var backgroundBitmap = BitmapFactory.decodeResource(appContext.resources, R.drawable.bg_empty)
        private var vignettingBitmap = BitmapFactory.decodeResource(appContext.resources, R.drawable.vignetting)
        private var barsBitmap = BitmapFactory.decodeResource(appContext.resources, R.drawable.bars)
        private var legendSecond = BitmapFactory.decodeResource(appContext.resources, R.drawable.legend_second)
        private var legendDate = BitmapFactory.decodeResource(appContext.resources, R.drawable.legend_date)
        private var legendDayOfWeek = BitmapFactory.decodeResource(appContext.resources, R.drawable.legend_day_week)
        private var legendSteps = BitmapFactory.decodeResource(appContext.resources, R.drawable.legend_steps)
        private var legendStepsHex = BitmapFactory.decodeResource(appContext.resources, R.drawable.legend_steps_hex)
        private var legendBattery = BitmapFactory.decodeResource(appContext.resources, R.drawable.legend_battery)
        private var legendBatteryHex = BitmapFactory.decodeResource(appContext.resources, R.drawable.legend_battery_hex)
        private var legendHeartRate = BitmapFactory.decodeResource(appContext.resources, R.drawable.legend_heart_rate)
        private val numbers = HexNumbers(appContext.resources)

        private var heartRate = 0
        private var heartRateTs = 0L
        private var stepCounter = 0
        private var touchTs = 0L
        private var touchCount = 0
        private val sensorManager = appContext.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        private var heartRateSensor: Sensor? = null
        private var stepPassiveMonitoringClient: androidx.health.services.client.PassiveMonitoringClient? = null
        private val mainHandler = Handler(Looper.getMainLooper())

        private var backgroundMinX = 0
        private var backgroundMinY = 0
        private var backgroundMaxX = 0
        private var backgroundMaxY = 0
        private var background: IntArray? = null
        private var aodStartTs = 0L
        private var lastAmbientUpdateTs = 0L
        private var lastAmbientUpdateX = 0
        private var lastAmbientUpdateY = 0

        override suspend fun init() {
            calendar.timeZone = TimeZone.getDefault()
            updateSensors()
        }

        override fun onDestroy() {
            heartRateSensor?.let { sensorManager.unregisterListener(heartRateListener, it) }
            heartRateSensor = null
            stepPassiveMonitoringClient?.clearPassiveListenerCallbackAsync()
            stepPassiveMonitoringClient = null
        }

        fun onTap() {
            val now = System.currentTimeMillis()
            touchCount = if (now - touchTs <= TOUCH_INTERVAL) {
                val next = touchCount + 1
                if (next > 3) 1 else next
            } else {
                1
            }
            touchTs = now
            invalidate()
        }

        override fun render(canvas: Canvas, bounds: Rect, zonedDateTime: ZonedDateTime) {
            val res = appContext.resources
            val now = System.currentTimeMillis()
            calendar.timeInMillis = zonedDateTime.toInstant().toEpochMilli()

            if (backgroundMinX == 0) backgroundMinX = -canvas.width / 2 / NUMBER_WIDTH
            if (backgroundMaxX == 0) backgroundMaxX = canvas.width / 2 / NUMBER_WIDTH + 1
            if (backgroundMinY == 0) backgroundMinY = -canvas.width / 2 / NUMBER_V_INTERVAL - 1
            if (backgroundMaxY == 0) backgroundMaxY = canvas.width / 2 / NUMBER_V_INTERVAL + 2

            var battery = 0
            val batteryIntent = appContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            if (batteryIntent != null) battery = batteryIntent.getIntExtra(BatteryManager.EXTRA_LEVEL, 0)

            val tappedDec = touchTs + TOUCH_DEC_DURATION >= now
            val tappedLegend = (touchTs + TOUCH_LEGEND_DURATION >= now) && touchCount == 3

            val hour = if (p.getInt(PREF_TIME_FORMAT, SettingsActivity.PREF_DEFAULT_TIME_FORMAT) ==
                SettingsActivity.PREF_TIME_FORMAT_12
            ) calendar.get(Calendar.HOUR) else calendar.get(Calendar.HOUR_OF_DAY)

            var timeSystem = p.getInt(PREF_TIME_SYSTEM, SettingsActivity.PREF_DEFAULT_TIME_SYSTEM)
            if (timeSystem == SettingsActivity.PREF_VALUE_TIME_DEC_ON_TAP) {
                timeSystem = if (tappedDec) SettingsActivity.PREF_VALUE_TIME_DEC else SettingsActivity.PREF_VALUE_TIME_HEX
            }
            timeSystem = when (timeSystem) {
                SettingsActivity.PREF_VALUE_TIME_HEX -> ENDIANNESS_LITTLE_ENDIAN
                else -> ENDIANNESS_FAKE_HEX
            }

            if (renderParameters.drawMode != DrawMode.AMBIENT) {
                val endianness = if (p.getInt(PREF_ENDIANNESS, SettingsActivity.PREF_DEFAULT_ENDIANNESS) ==
                    SettingsActivity.PREF_VALUE_ENDIANNESS_LITTLE_ENDIAN
                ) ENDIANNESS_LITTLE_ENDIAN else ENDIANNESS_BIG_ENDIAN

                canvas.drawBitmap(
                    backgroundBitmap,
                    (canvas.width / 2 - backgroundBitmap.width / 2).toFloat(),
                    (canvas.height / 2 - backgroundBitmap.height / 2 + BACKGROUND_Y_OFFSET).toFloat(),
                    null
                )

                val backgroundMode = p.getInt(PREF_BACKGROUND, SettingsActivity.PREF_DEFAULT_BACKGROUND)
                if (background == null || p.getBoolean(PREF_BACKGROUND_REDRAW, false)) {
                    background = IntArray((backgroundMaxX - backgroundMinX + 1) * (backgroundMaxY - backgroundMinY + 1))
                    if (backgroundMode == SettingsActivity.PREF_VALUE_BACKGROUND_RANDOM_ONCE) {
                        for (i in background!!.indices) background!![i] = (Math.random() * 256).toInt()
                    } else if (backgroundMode == SettingsActivity.PREF_VALUE_BACKGROUND_ZEROS) {
                        Arrays.fill(background!!, 0)
                    }
                    p.edit().putBoolean(PREF_BACKGROUND_REDRAW, false).apply()
                }
                if (backgroundMode == SettingsActivity.PREF_VALUE_BACKGROUND_RANDOM) {
                    for (i in background!!.indices) background!![i] = (Math.random() * 256).toInt()
                }
                var idx = 0
                for (x in backgroundMinX..backgroundMaxX) {
                    for (y in backgroundMinY until backgroundMaxY) {
                        drawNumberAtPos(canvas, background!![idx++], HexNumbers.COLORS_CYAN.toInt(), x.toFloat(), y.toFloat())
                    }
                }

                if (tappedLegend && p.getInt(PREF_BARS, SettingsActivity.PREF_DEFAULT_BARS) == SettingsActivity.PREF_VALUE_BARS_SHOW) {
                    drawCentered(canvas, barsBitmap, BACKGROUND_Y_OFFSET)
                }

                drawNumber(canvas, hour, timeSystem, 1, HexNumbers.COLORS_WHITE.toInt(), 0f, 0f)
                drawNumber(canvas, calendar.get(Calendar.MINUTE), timeSystem, 1, HexNumbers.COLORS_WHITE.toInt(), 1f, 0f)
                drawNumber(canvas, calendar.get(Calendar.SECOND), timeSystem, 1, HexNumbers.COLORS_CYAN.toInt(), 2f, 0f)
                if (tappedLegend) drawCentered(canvas, legendSecond, 0)

                var dateSystem = p.getInt(PREF_DATE, SettingsActivity.PREF_DEFAULT_DATE)
                if (dateSystem != SettingsActivity.PREF_VALUE_HIDE) {
                    if (dateSystem == SettingsActivity.PREF_VALUE_COMMON_DEC_ON_TAP) {
                        dateSystem = if (tappedDec) SettingsActivity.PREF_VALUE_COMMON_DEC else SettingsActivity.PREF_VALUE_COMMON_HEX
                    }
                    dateSystem = if (dateSystem == SettingsActivity.PREF_VALUE_COMMON_HEX) ENDIANNESS_LITTLE_ENDIAN else ENDIANNESS_FAKE_HEX
                    drawNumber(canvas, calendar.get(Calendar.DAY_OF_MONTH), dateSystem, 1, HexNumbers.COLORS_CYAN.toInt(), 2f, 1f)
                    drawNumber(canvas, calendar.get(Calendar.MONTH) + 1, dateSystem, 1, HexNumbers.COLORS_CYAN.toInt(), 2f, -1f)
                    drawNumber(canvas, calendar.get(Calendar.YEAR), dateSystem, 1, HexNumbers.COLORS_CYAN.toInt(), 1f, -1f)
                    if (tappedLegend) drawCentered(canvas, legendDate, 0)
                }

                val dayOfWeekMode = p.getInt(PREF_DAY_WEEK, SettingsActivity.PREF_DEFAULT_DAY_OF_THE_WEEK)
                if (dayOfWeekMode != SettingsActivity.PREF_VALUE_HIDE) {
                    var dayOfWeek = calendar.get(Calendar.DAY_OF_WEEK) - 1
                    if (dayOfWeek == 0 && dayOfWeekMode == SettingsActivity.PREF_VALUE_DAY_SUNDAY_7) dayOfWeek = 7
                    drawNumber(canvas, dayOfWeek, ENDIANNESS_FAKE_HEX, 1, HexNumbers.COLORS_CYAN.toInt(), 1f, 1f)
                    if (tappedLegend) drawCentered(canvas, legendDayOfWeek, 0)
                }

                var batterySystem = p.getInt(PREF_BATTERY, SettingsActivity.PREF_DEFAULT_BATTERY)
                if (batterySystem != SettingsActivity.PREF_VALUE_HIDE) {
                    batterySystem = when (batterySystem) {
                        SettingsActivity.PREF_VALUE_BATTERY_HEX_0_FF_TAP ->
                            if (tappedDec) SettingsActivity.PREF_VALUE_BATTERY_DEC_0_100 else SettingsActivity.PREF_VALUE_BATTERY_HEX_0_FF
                        SettingsActivity.PREF_VALUE_BATTERY_HEX_0_64_TAP ->
                            if (tappedDec) SettingsActivity.PREF_VALUE_BATTERY_DEC_0_100 else SettingsActivity.PREF_VALUE_BATTERY_HEX_0_64
                        else -> batterySystem
                    }
                    when (batterySystem) {
                        SettingsActivity.PREF_VALUE_BATTERY_HEX_0_64 ->
                            drawNumber(canvas, battery, ENDIANNESS_LITTLE_ENDIAN, 1, HexNumbers.COLORS_CYAN.toInt(), -1f, 0f)
                        SettingsActivity.PREF_VALUE_BATTERY_HEX_0_FF ->
                            drawNumber(canvas, battery * 255 / 100, ENDIANNESS_LITTLE_ENDIAN, 1, HexNumbers.COLORS_CYAN.toInt(), -1f, 0f)
                        else ->
                            drawNumber(canvas, battery, ENDIANNESS_FAKE_HEX, 2, HexNumbers.COLORS_CYAN.toInt(), -2f, 0f)
                    }
                    if (tappedLegend) {
                        val legend = if (batterySystem == SettingsActivity.PREF_VALUE_BATTERY_DEC_0_100) legendBattery else legendBatteryHex
                        drawCentered(canvas, legend, 0)
                    }
                }

                var heartRateSystem = p.getInt(PREF_HEART_RATE, SettingsActivity.PREF_DEFAULT_HEART_RATE)
                if (heartRateSystem != SettingsActivity.PREF_VALUE_HIDE) {
                    if (heartRateTs + MAX_HEART_RATE_AGE < now && heartRate != 0) heartRate = 0
                    if (heartRateSystem == SettingsActivity.PREF_VALUE_COMMON_DEC_ON_TAP) {
                        heartRateSystem = if (tappedDec) SettingsActivity.PREF_VALUE_COMMON_DEC else SettingsActivity.PREF_VALUE_COMMON_HEX
                    }
                    if (heartRateSystem == SettingsActivity.PREF_VALUE_COMMON_HEX) {
                        drawNumber(canvas, heartRate, endianness, 2, HexNumbers.COLORS_CYAN.toInt(), -1f, -1f)
                    } else {
                        drawNumber(canvas, heartRate, ENDIANNESS_FAKE_HEX, 2, HexNumbers.COLORS_CYAN.toInt(), -1f, -1f)
                    }
                    if (tappedLegend) drawCentered(canvas, legendHeartRate, 0)
                }

                var stepsSystem = p.getInt(PREF_STEPS, SettingsActivity.PREF_DEFAULT_STEPS)
                if (stepsSystem != SettingsActivity.PREF_VALUE_HIDE) {
                    if (stepsSystem == SettingsActivity.PREF_VALUE_COMMON_DEC_ON_TAP) {
                        stepsSystem = if (tappedDec) SettingsActivity.PREF_VALUE_COMMON_DEC else SettingsActivity.PREF_VALUE_COMMON_HEX
                    }
                    if (stepsSystem == SettingsActivity.PREF_VALUE_COMMON_HEX) {
                        drawNumber(canvas, stepCounter, endianness, 2, HexNumbers.COLORS_CYAN.toInt(), -1f, 1f)
                    } else {
                        drawNumber(canvas, stepCounter, ENDIANNESS_FAKE_HEX, 3, HexNumbers.COLORS_CYAN.toInt(), -2f, 1f)
                    }
                    if (tappedLegend) {
                        val legend = if (stepsSystem == SettingsActivity.PREF_VALUE_COMMON_DEC) legendSteps else legendStepsHex
                        drawCentered(canvas, legend, 0)
                    }
                }

                if (!tappedLegend && p.getInt(PREF_BARS, SettingsActivity.PREF_DEFAULT_BARS) == SettingsActivity.PREF_VALUE_BARS_SHOW) {
                    drawCentered(canvas, barsBitmap, BACKGROUND_Y_OFFSET)
                }

                if (p.getInt(PREF_VIGNETTING, res.getInteger(R.integer.default_vignetting)) == SettingsActivity.PREF_VALUE_ENABLED) {
                    canvas.drawBitmap(
                        vignettingBitmap,
                        Rect(0, 0, vignettingBitmap.width, vignettingBitmap.height),
                        Rect(0, 0, canvas.width, canvas.height),
                        null
                    )
                }

                aodStartTs = 0
                lastAmbientUpdateX = 0
                lastAmbientUpdateY = 0
            } else {
                if (aodStartTs == 0L) aodStartTs = now
                canvas.drawColor(Color.BLACK)
                var x = 0
                var y = 0
                if (p.getInt(PREF_ANTI_BURN_IN, SettingsActivity.PREF_DEFAULT_ANTI_BURN_IN) == SettingsActivity.PREF_VALUE_ENABLED &&
                    aodStartTs + ANTI_BURN_IN_TIME < now
                ) {
                    if (lastAmbientUpdateTs + ANTI_BURN_IN_TIME_MIN_PERIOD < now) {
                        y = (Math.round(Math.random() * Math.max(1, backgroundMaxY - 3))).toInt()
                        if (Math.round(Math.random()) == 0L) y = -y
                        x = if (y == 0 || !res.getBoolean(R.bool.is_round)) {
                            (Math.round(Math.random() * Math.max(1, backgroundMaxX - 2))).toInt()
                        } else if (y > -(backgroundMaxY - 3) && y < backgroundMaxY - 3) {
                            Math.round(Math.random()).toInt()
                        } else 0
                        if (Math.round(Math.random()) == 0L) x = -x
                        lastAmbientUpdateX = x
                        lastAmbientUpdateY = y
                        lastAmbientUpdateTs = now
                    } else {
                        x = lastAmbientUpdateX
                        y = lastAmbientUpdateY
                    }
                }
                drawNumber(canvas, hour, timeSystem, 1, HexNumbers.COLORS_DARK.toInt(), x.toFloat(), y.toFloat())
                drawNumber(canvas, calendar.get(Calendar.MINUTE), timeSystem, 1, HexNumbers.COLORS_DARK.toInt(), (1 + x).toFloat(), y.toFloat())
            }
        }

        override fun renderHighlightLayer(canvas: Canvas, bounds: Rect, zonedDateTime: ZonedDateTime) {
            // No highlight layer needed; the whole watch face is drawn by render().
        }

        private val p: SharedPreferences
            get() = prefs

        private fun drawCentered(canvas: Canvas, bitmap: android.graphics.Bitmap, yOffset: Int) {
            canvas.drawBitmap(
                bitmap,
                (canvas.width / 2 - bitmap.width / 2).toFloat(),
                (canvas.height / 2 - bitmap.height / 2 + yOffset).toFloat(),
                null
            )
        }

        private fun drawNumber(
            canvas: Canvas, number: Int, endianness: Int, size: Int, color: Int, left: Float, top: Float
        ) {
            for (i in 0 until size) {
                val digit = when (endianness) {
                    ENDIANNESS_BIG_ENDIAN -> (number shr ((size - i - 1) * 8)) and 0xFF
                    ENDIANNESS_LITTLE_ENDIAN -> (number shr (i * 8)) and 0xFF
                    else -> {
                        val base = Math.pow(100.0, (size - i - 1).toDouble()).toInt()
                        val d = number / base % 100
                        (d % 10) or ((d / 10) * 16)
                    }
                }
                drawNumberAtPos(canvas, digit, color, left + i, top)
            }
        }

        private fun drawNumberAtPos(canvas: Canvas, number: Int, color: Int, left: Float, top: Float) {
            val bitmap = numbers.GetNumber(number, color)
            canvas.drawBitmap(bitmap, canvas.width / 2 + (left - 1) * NUMBER_WIDTH, canvas.height / 2 + top * NUMBER_V_INTERVAL - 24, null)
        }

        private fun updateSensors() {
            if (ContextCompat.checkSelfPermission(appContext, Manifest.permission.BODY_SENSORS) == PackageManager.PERMISSION_GRANTED &&
                p.getInt(PREF_HEART_RATE, SettingsActivity.PREF_DEFAULT_HEART_RATE) != SettingsActivity.PREF_VALUE_HIDE
            ) {
                if (heartRateSensor == null) {
                    heartRateSensor = sensorManager.getDefaultSensor(Sensor.TYPE_HEART_RATE)
                    heartRateSensor?.let { sensorManager.registerListener(heartRateListener, it, SensorManager.SENSOR_DELAY_NORMAL, mainHandler) }
                }
            } else if (heartRateSensor != null) {
                heartRateSensor?.let { sensorManager.unregisterListener(heartRateListener, it) }
                heartRateSensor = null
                heartRate = 0
            }

            if (ContextCompat.checkSelfPermission(appContext, Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED &&
                p.getInt(PREF_STEPS, SettingsActivity.PREF_DEFAULT_STEPS) != SettingsActivity.PREF_VALUE_HIDE
            ) {
                if (stepPassiveMonitoringClient == null) {
                    stepPassiveMonitoringClient = HealthServices.getClient(appContext).passiveMonitoringClient
                    val dataTypes = HashSet<androidx.health.services.client.data.DataType<*, *>>()
                    dataTypes.add(DataType.STEPS_DAILY)
                    @Suppress("UNCHECKED_CAST")
                    val config = PassiveListenerConfig.builder()
                        .setDataTypes(dataTypes as Set<androidx.health.services.client.data.DataType<*, *>>)
                        .build()
                    stepPassiveMonitoringClient?.setPassiveListenerCallback(config, stepListener)
                }
            } else if (stepPassiveMonitoringClient != null) {
                stepPassiveMonitoringClient?.clearPassiveListenerCallbackAsync()
                stepPassiveMonitoringClient = null
            }
        }

        private val heartRateListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                if (event.sensor.type == Sensor.TYPE_HEART_RATE && event.values[0].toInt() != 0) {
                    heartRate = event.values[0].toInt()
                    heartRateTs = System.currentTimeMillis()
                }
            }

            override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}
        }

        private val stepListener = object : PassiveListenerCallback {
            override fun onNewDataPointsReceived(dataPoints: DataPointContainer) {
                super.onNewDataPointsReceived(dataPoints)
                val dps: List<IntervalDataPoint<Long>> = dataPoints.getData(DataType.STEPS_DAILY)
                val bootInstant = Instant.ofEpochMilli(System.currentTimeMillis() - SystemClock.elapsedRealtime())
                var ts = 0L
                var steps = 0L
                for (dp in dps) {
                    val endTime = dp.getEndInstant(bootInstant)
                    if (endTime.toEpochMilli() > ts) {
                        ts = endTime.toEpochMilli()
                        steps = dp.value
                    }
                }
                stepCounter = steps.toInt()
            }
        }

        companion object {
            private const val TAG = "hex_watchface"
            private const val TOUCH_DEC_DURATION = 5000L
            private const val TOUCH_LEGEND_DURATION = 2500L
            private const val TOUCH_INTERVAL = 500L
            private const val MAX_HEART_RATE_AGE = 10000L
            private const val ANTI_BURN_IN_TIME = 3000L
            private const val ANTI_BURN_IN_TIME_MIN_PERIOD = 58000L
            private const val NUMBER_WIDTH = 78
            private const val NUMBER_V_INTERVAL = 56
            private const val BACKGROUND_Y_OFFSET = -54
            private const val ENDIANNESS_LITTLE_ENDIAN = 0
            private const val ENDIANNESS_BIG_ENDIAN = 1
            private const val ENDIANNESS_FAKE_HEX = 2

            private const val PREF_TIME_FORMAT = "time_format"
            private const val PREF_TIME_SYSTEM = "time_system"
            private const val PREF_DATE = "date"
            private const val PREF_DAY_WEEK = "day_week"
            private const val PREF_HEART_RATE = "heart_rate"
            private const val PREF_STEPS = "steps"
            private const val PREF_BATTERY = "battery"
            private const val PREF_ENDIANNESS = "endianness"
            private const val PREF_BACKGROUND = "background"
            private const val PREF_BACKGROUND_REDRAW = "background_redraw"
            private const val PREF_BARS = "bars"
            private const val PREF_VIGNETTING = "vignetting"
            private const val PREF_ANTI_BURN_IN = "anti_burn_in"
        }
    }
}
