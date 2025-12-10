//
//  TokenCountingTests.swift
//  FoundationModelsToolsTests
//
//  Tests for token counting and context window management utilities.
//

import Foundation
import Testing
@testable import FoundationModelsTools

@Suite("Token Counting Tests")
struct TokenCountingTests {

  // MARK: - estimateTokens(from:) Tests

  @Test("Empty string returns zero tokens")
  func emptyStringReturnsZero() {
    let tokens = estimateTokens(from: "")
    #expect(tokens == 0)
  }

  @Test("Single character returns at least one token")
  func singleCharacterReturnsOne() {
    let tokens = estimateTokens(from: "a")
    #expect(tokens >= 1)
  }

  @Test("Short text returns expected token count")
  func shortTextTokenCount() {
    // "Hello, world!" is 13 characters
    // At 4.75 chars/token, should be ~3 tokens
    let tokens = estimateTokens(from: "Hello, world!")
    #expect(tokens >= 2 && tokens <= 4)
  }

  @Test("Longer text scales appropriately")
  func longerTextScales() {
    let shortText = "Hello"
    let longText = String(repeating: "Hello ", count: 100)

    let shortTokens = estimateTokens(from: shortText)
    let longTokens = estimateTokens(from: longText)

    #expect(longTokens > shortTokens * 50)
  }

  // MARK: - estimateTokensConservative(from:) Tests

  @Test("Conservative estimate is higher than standard estimate")
  func conservativeEstimateIsHigher() {
    let text = "This is a sample text for testing token estimation."
    let standard = estimateTokens(from: text)
    let conservative = estimateTokensConservative(from: text)

    #expect(conservative >= standard)
  }

  @Test("Conservative empty string returns zero")
  func conservativeEmptyStringReturnsZero() {
    let tokens = estimateTokensConservative(from: "")
    #expect(tokens == 0)
  }
}

@Suite("Token Estimation Accuracy Tests")
struct TokenEstimationAccuracyTests {

  @Test("Token estimation is consistent")
  func tokenEstimationIsConsistent() {
    let text = "The quick brown fox jumps over the lazy dog."

    let tokens1 = estimateTokens(from: text)
    let tokens2 = estimateTokens(from: text)

    #expect(tokens1 == tokens2)
  }

  @Test("Whitespace is counted in tokens")
  func whitespaceIsCounted() {
    let noSpaces = "HelloWorld"
    let withSpaces = "Hello World"

    let noSpaceTokens = estimateTokens(from: noSpaces)
    let withSpaceTokens = estimateTokens(from: withSpaces)

    // With spaces should have slightly more tokens due to extra character
    #expect(withSpaceTokens >= noSpaceTokens)
  }

  @Test("Special characters are handled")
  func specialCharactersHandled() {
    let text = "Hello! @#$%^&*() World"
    let tokens = estimateTokens(from: text)

    #expect(tokens > 0)
  }

  @Test("Unicode characters are handled")
  func unicodeCharactersHandled() {
    let text = "你好, world! 👋" // This string contains CJK characters and emoji.
    let tokens = estimateTokens(from: text)
    // The string has 12 characters (grapheme clusters). Expected tokens: ceil(12 / 4.75) = 3
    #expect(tokens >= 2 && tokens <= 4)
  }

  @Test("Newlines are handled")
  func newlinesHandled() {
    let text = "Line 1\nLine 2\nLine 3"
    let tokens = estimateTokens(from: text)

    #expect(tokens > 0)
  }
}
