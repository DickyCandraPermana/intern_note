package com.example.intern_noter.widget

import android.animation.ObjectAnimator
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.example.intern_noter.R
import java.util.Calendar

class QuickNoteActivity : Activity() {

    private lateinit var dbHelper: WidgetDbHelper
    private lateinit var scrim: FrameLayout
    private lateinit var card: LinearLayout
    private lateinit var tvDate: TextView
    private lateinit var chipContainer: LinearLayout
    private lateinit var etNote: EditText
    private lateinit var tvError: TextView
    private lateinit var btnCancel: Button
    private lateinit var btnSave: Button

    private var selectedModul: String = ""
    private var selectedProject: String = ""
    private var isSaving: Boolean = false
    private val tagChipViews = mutableListOf<Pair<QuickNoteTag, TextView>>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_quick_note)

        window.setSoftInputMode(
            WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE or
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE,
        )

        dbHelper = WidgetDbHelper(applicationContext)

        scrim = findViewById(R.id.quick_note_scrim)
        card = findViewById(R.id.quick_note_card)
        tvDate = findViewById(R.id.tv_quick_note_date)
        chipContainer = findViewById(R.id.chip_container)
        etNote = findViewById(R.id.et_quick_note)
        tvError = findViewById(R.id.tv_quick_note_error)
        btnCancel = findViewById(R.id.btn_quick_note_cancel)
        btnSave = findViewById(R.id.btn_quick_note_save)

        scrim.setOnClickListener { finish() }
        card.setOnClickListener {
            // Swallow clicks inside card so only taps on outer scrim close the overlay.
        }
        btnCancel.setOnClickListener { finish() }
        btnSave.setOnClickListener { saveNote() }

        etNote.addTextChangedListener(
            object : TextWatcher {
                override fun beforeTextChanged(
                    s: CharSequence?,
                    start: Int,
                    count: Int,
                    after: Int,
                ) = Unit

                override fun onTextChanged(
                    s: CharSequence?,
                    start: Int,
                    before: Int,
                    count: Int,
                ) {
                    if (!s.isNullOrBlank() && tvError.visibility == View.VISIBLE) {
                        tvError.visibility = View.GONE
                    }
                }

                override fun afterTextChanged(s: Editable?) = Unit
            },
        )

        refreshUi()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        refreshUi()
    }

    override fun onResume() {
        super.onResume()
        focusNoteInput()
    }

    override fun onDestroy() {
        if (::dbHelper.isInitialized) {
            dbHelper.close()
        }
        super.onDestroy()
    }

    private fun refreshUi() {
        isSaving = false
        btnSave.isEnabled = true
        tvDate.text = IndonesianDates.formatLongDayDate(Calendar.getInstance())
        tvError.visibility = View.GONE
        populateChips()
        focusNoteInput()
    }

    private fun focusNoteInput() {
        etNote.requestFocus()
        etNote.post {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.showSoftInput(etNote, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    private fun populateChips() {
        chipContainer.removeAllViews()
        tagChipViews.clear()

        val noteContext = dbHelper.getQuickNoteContext()
        selectedModul = noteContext.defaultTag?.modul ?: ""
        selectedProject = noteContext.defaultTag?.project ?: ""

        val emptyTag = QuickNoteTag("", "")
        addTagChip(emptyTag, "Tanpa Tag")

        for (tag in noteContext.recentTags) {
            addTagChip(tag, tag.displayLabel())
        }

        updateTagChipStyles()

        for (preset in noteContext.quickPresets) {
            addPresetPill(preset)
        }
    }

    private fun addTagChip(tag: QuickNoteTag, label: String) {
        val chip = createChipView(label).apply {
            setOnClickListener {
                selectedModul = tag.modul
                selectedProject = tag.project
                updateTagChipStyles()
            }
        }
        tagChipViews.add(tag to chip)
        chipContainer.addView(chip)
    }

    private fun addPresetPill(preset: String) {
        val pill = createChipView("+ $preset").apply {
            setBackgroundResource(R.drawable.widget_input_bg)
            setTextColor(getColor(R.color.widget_accent))
            setOnClickListener {
                val current = etNote.text?.toString() ?: ""
                val updated = if (current.trim().isEmpty()) {
                    preset
                } else {
                    "${current.trimEnd()}\n$preset"
                }
                etNote.setText(updated)
                etNote.setSelection(updated.length)
                tvError.visibility = View.GONE
                focusNoteInput()
            }
        }
        chipContainer.addView(pill)
    }

    private fun createChipView(label: String): TextView {
        val horizontalPad = dpToPx(12)
        val verticalPad = dpToPx(8)
        val chipMarginEnd = dpToPx(8)
        val chipMinHeight = dpToPx(36)

        return TextView(this).apply {
            text = label
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            gravity = Gravity.CENTER
            minHeight = chipMinHeight
            setPadding(horizontalPad, verticalPad, horizontalPad, verticalPad)
            isClickable = true
            isFocusable = true
            maxLines = 1
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                setMarginEnd(chipMarginEnd)
            }
        }
    }

    private fun updateTagChipStyles() {
        for ((tag, chip) in tagChipViews) {
            val isSelected = tag.modul == selectedModul && tag.project == selectedProject
            if (isSelected) {
                chip.setBackgroundResource(R.drawable.chip_bg_selected)
                chip.setTextColor(getColor(R.color.widget_accent))
                chip.setTypeface(null, Typeface.BOLD)
            } else {
                chip.setBackgroundResource(R.drawable.chip_bg)
                chip.setTextColor(getColor(R.color.widget_ink_primary))
                chip.setTypeface(null, Typeface.NORMAL)
            }
        }
    }

    private fun saveNote() {
        if (isSaving) return
        val trimmedText = etNote.text?.toString()?.trim().orEmpty()
        if (trimmedText.isEmpty()) {
            tvError.text = "Catatan tidak boleh kosong"
            tvError.visibility = View.VISIBLE
            ObjectAnimator.ofFloat(
                card,
                "translationX",
                0f,
                -14f,
                14f,
                -10f,
                10f,
                -6f,
                6f,
                0f,
            ).setDuration(260).start()
            focusNoteInput()
            return
        }

        isSaving = true
        btnSave.isEnabled = false
        try {
            dbHelper.insertQuickNote(
                todayIso = IndonesianDates.todayIso(Calendar.getInstance()),
                description = trimmedText,
                modul = selectedModul,
                project = selectedProject,
            )
            TodayNoteWidgetProvider.updateAllWidgets(applicationContext)

            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.hideSoftInputFromWindow(etNote.windowToken, 0)

            Toast.makeText(
                applicationContext,
                "Tersimpan ke log hari ini",
                Toast.LENGTH_SHORT,
            ).show()
            finish()
        } catch (e: Exception) {
            isSaving = false
            btnSave.isEnabled = true
            tvError.text = "Gagal menyimpan catatan: ${e.message ?: "kesalahan database"}"
            tvError.visibility = View.VISIBLE
        }
    }

    private fun dpToPx(dp: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp.toFloat(),
            resources.displayMetrics,
        ).toInt()
    }
}
