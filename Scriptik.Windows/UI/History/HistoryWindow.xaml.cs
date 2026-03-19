using System.Windows;
using System.Windows.Controls;
using Scriptik.Windows.Services;

namespace Scriptik.Windows.UI.History;

public partial class HistoryWindow : Window
{
    private readonly HistoryManager _history;
    private string _searchText = "";

    public HistoryWindow(HistoryManager history)
    {
        InitializeComponent();
        _history = history;
        _history.Refresh();
        RefreshList();
    }

    private void RefreshList()
    {
        var entries = _history.Entries;

        if (!string.IsNullOrEmpty(_searchText))
        {
            entries = entries
                .Where(e => e.Content.Contains(_searchText, StringComparison.OrdinalIgnoreCase))
                .ToList();
        }

        EntryList.ItemsSource = entries;
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        _searchText = SearchBox.Text;
        if (SearchPlaceholder is not null)
            SearchPlaceholder.Visibility = string.IsNullOrEmpty(_searchText)
                ? Visibility.Visible : Visibility.Collapsed;
        RefreshList();
    }

    private void EntryList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (EntryList.SelectedItem is HistoryManager.Entry entry)
        {
            EmptyState.Visibility = Visibility.Collapsed;
            DetailPanel.Visibility = Visibility.Visible;
            DetailDate.Text = entry.Date.ToString("f");
            DetailContent.Text = entry.Content;
        }
        else
        {
            EmptyState.Visibility = Visibility.Visible;
            DetailPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void CopyEntry_Click(object sender, RoutedEventArgs e)
    {
        if (EntryList.SelectedItem is HistoryManager.Entry entry)
            ClipboardService.SetText(entry.Content);
    }

    private void DeleteEntry_Click(object sender, RoutedEventArgs e)
    {
        if (EntryList.SelectedItem is HistoryManager.Entry entry)
        {
            _history.Delete(entry);
            RefreshList();
        }
    }

    private void CopyDetail_Click(object sender, RoutedEventArgs e)
    {
        if (EntryList.SelectedItem is HistoryManager.Entry entry)
            ClipboardService.SetText(entry.Content);
    }
}
