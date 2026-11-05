// Zephyr Design System - SwiftUI Extensions
// Hand-written extensions (committed to git)

import SwiftUI
import ZephyrCore

@MainActor
public class DesignTokens: ObservableObject {
    // Design Token generated constants are in AppTokens.swift
    // This class provides theme switching and convenience accessors

    @Published public var isDarkTheme: Bool = true

    public static let shared = DesignTokens()

    // Convenience accessors for commonly used tokens
    public var textPrimary: Color {
        isDarkTheme ? AppColors.textPrimary : AppColors.textPrimaryLight
    }

    public var textSecondary: Color {
        isDarkTheme ? AppColors.textSecondary : AppColors.textSecondaryLight
    }

    public var bgElevated: Color {
        isDarkTheme ? AppColors.bgElevated : AppColors.bgElevatedLight
    }

    public var bgSecondary: Color {
        isDarkTheme ? AppColors.bgSecondary : AppColors.bgSecondaryLight
    }

    public var borderDefault: Color {
        isDarkTheme ? AppColors.borderDefault : AppColors.borderDefaultLight
    }

    public var accentPrimary: Color {
        isDarkTheme ? AppColors.colorBlue500 : AppColors.colorBlue600
    }

    public var danger: Color {
        isDarkTheme ? AppColors.colorDanger : AppColors.colorDangerLight
    }

    public var warning: Color {
        isDarkTheme ? AppColors.colorWarning : AppColors.colorWarningLight
    }

    public var success: Color {
        isDarkTheme ? AppColors.colorSuccess : AppColors.colorSuccessLight
    }

    public var info: Color {
        isDarkTheme ? AppColors.colorInfo : AppColors.colorInfoLight
    }
}
